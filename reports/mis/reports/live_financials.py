"""Live financials from Zoho: trial balance, P&L, Balance Sheet and Executive Summary for any columns.

The date filter's columns (`periods.Col`: split blocks, Total, comparison periods) are cut into GL
segments (`monthly_trial_balance.segments`): one `/reports/generalledger` call per segment plus one
opening call. Segments are cached in this process, so repeat and overlapping views make no Zoho call:

- a segment is fresh for MIS_LIVE_TTL seconds (default 900 = 15 min); `refresh=True` re-fetches
  segments older than a minute, so a Refresh button can't hammer Zoho;
- one Zoho fetch at a time: a request that needs Zoho waits up to a minute for the fetch in progress
  (then reuses what it brought), else `Busy`;
- when Zoho fails, an expired copy of the segment is served and the result says `stale: true` with
  its `fetched_at`; with nothing to fall back on, `ZohoDown`.

Categories come from the Category Master (COA snapshot + overrides) on every request, so a changed
mapping shows at once. The web API serves this only with MIS_LIVE_FINANCIALS=1.
"""

from __future__ import annotations

import os
import re
import threading
import time
from datetime import date, datetime
from typing import Any, Callable

from reports import monthly_trial_balance as mtb
from reports import periods
from reports.financials import (
    TOTAL, Statement, build_balance_sheet, build_executive_summary, build_profit_and_loss,
)

TTL = float(os.getenv("MIS_LIVE_TTL") or 900)
REFRESH_AGE = 60
BUSY_WAIT = 60
KEEP = 24 * 3600  # expired segments stay this long for the stale fallback
MAX_CALLS = 100
STATEMENTS = ("Executive Summary", "PL", "BS")
_COMPARE = re.compile(r"^p[-+]\d+$")
_RESERVED = set(mtb.BASE_COLUMNS + mtb.TAIL_COLUMNS) | {"balances"}  # row fields a column key would overwrite


def enabled() -> bool:
    return os.getenv("MIS_LIVE_FINANCIALS") == "1"


class Busy(Exception):
    """Another Zoho fetch held the line for longer than BUSY_WAIT."""


class ZohoDown(Exception):
    """Zoho failed and there was no earlier copy to fall back on."""


class GLCache:
    """GL movement per date range, fetched from Zoho one range at a time and kept in memory."""

    def __init__(self, fetch: Callable[[date, date], mtb.Moves] | None = None, *, ttl: float = TTL,
                 clock: Callable[[], float] = time.time, log: Callable[[str], None] = print):
        self._fetch = fetch
        self.ttl = ttl
        self.clock = clock
        self.log = log
        self._entries: dict[tuple[date, date], tuple[float, mtb.Moves]] = {}
        self._mu = threading.Lock()    # guards _entries
        self._zoho = threading.Lock()  # one Zoho fetch at a time
        self._client: Any = None

    def _from_zoho(self, a: date, b: date) -> mtb.Moves:
        if self._fetch:
            return self._fetch(a, b)
        if self._client is None:  # reuses the cached access token; no OAuth refresh per request
            from zoho_client import ZohoClient
            self._client = ZohoClient()
        return mtb._movement(self._client, a, b)

    def _stale(self, ranges: list[tuple[date, date]], max_age: float) -> list[tuple[date, date]]:
        now = self.clock()
        with self._mu:
            return [r for r in dict.fromkeys(ranges)
                    if r not in self._entries or now - self._entries[r][0] > max_age]

    def get(self, ranges: list[tuple[date, date]], *, refresh: bool = False) -> tuple[list[mtb.Moves], dict[str, Any]]:
        """→ (Moves per range, {fetched_at, stale, zoho_calls})."""
        max_age = REFRESH_AGE if refresh else self.ttl
        calls = 0
        if self._stale(ranges, max_age):
            if not self._zoho.acquire(timeout=BUSY_WAIT):
                raise Busy("Zoho is busy with another report. Try again in a minute.")
            try:
                error: Exception | None = None
                for r in self._stale(ranges, max_age):  # again: the fetch we waited for may have brought them
                    if error is None:
                        try:
                            self.log(f"live GL {r[0]} → {r[1]}")
                            moves = self._from_zoho(*r)
                            calls += 1
                            with self._mu:
                                self._entries[r] = (self.clock(), moves)
                            continue
                        except Exception as exc:  # Zoho down / timeout / rate limit: no more calls this time
                            error = exc
                            self.log(f"live GL failed: {exc}")
                    with self._mu:
                        if r not in self._entries:
                            raise ZohoDown(f"Zoho unavailable: {error}") from error
            finally:
                self._zoho.release()
            self._prune()
        with self._mu:
            got = [self._entries[r] for r in ranges]
        oldest = min(t for t, _ in got)
        return [m for _, m in got], {
            "fetched_at": datetime.fromtimestamp(oldest).isoformat(timespec="seconds"),
            "stale": self.clock() - oldest > self.ttl,
            "zoho_calls": calls,
        }

    def _prune(self) -> None:
        cutoff = self.clock() - max(KEEP, self.ttl)
        with self._mu:
            for r in [r for r, (t, _) in self._entries.items() if t < cutoff]:
                del self._entries[r]


_cache = GLCache()


def _fy_month(snapshot: dict[str, Any]) -> int:
    month = int(snapshot.get("fiscal_year_start_month") or 0)
    if not 1 <= month <= 12:
        raise ValueError("fiscal year start month unknown: refresh the chart of accounts (main.py category-master)")
    return month


def _ledger(cols: list[periods.Col], snapshot: dict[str, Any], refresh: bool,
            cache: GLCache | None) -> tuple[mtb.Ledger, dict[str, Any]]:
    clash = {c.key for c in cols} & _RESERVED
    if clash:
        raise ValueError(f"column key {sorted(clash)[0]!r} is reserved")
    fy_month = _fy_month(snapshot)
    segs = mtb.segments([(c.start, c.end) for c in cols], fy_month)
    if len(segs) + 1 > MAX_CALLS:
        raise ValueError(f"this view needs {len(segs) + 1} Zoho calls (at most {MAX_CALLS}): "
                         "shorten the range, split by a longer period or drop comparisons")
    opening = (mtb.BOOKS_EPOCH, segs[0][0] - mtb.DAY)
    moves, meta = (cache or _cache).get([opening, *segs], refresh=refresh)
    return mtb.Ledger(segs, moves[0], moves[1:], fy_month), meta


def _nonzero(values: dict[str, float]) -> bool:
    return any(abs(v) >= 0.005 for v in values.values())


def trial_balance(cols: list[periods.Col], snapshot: dict[str, Any], overrides: dict[str, dict[str, str]],
                  *, refresh: bool = False, cache: GLCache | None = None) -> dict[str, Any]:
    """Opening (before the first column), one net per column, closing (after the last)."""
    ledger, meta = _ledger(cols, snapshot, refresh, cache)
    rows = mtb.tb_rows(ledger, snapshot, overrides, [(c.key, c.start, c.end) for c in cols])
    rows.sort(key=lambda r: (r["pl_bs"] != "BS", r["category"], r["account_code"] or "zzzz", r["account_name"].lower()))
    start, end = periods.span(cols)
    return {"months": [c.key for c in cols], "rows": rows, "from": start.isoformat(), "to": end.isoformat(), **meta}


def _flow_rows(ledger: mtb.Ledger, snapshot: dict[str, Any], overrides: dict[str, dict[str, str]],
               cols: list[periods.Col]) -> list[dict[str, Any]]:
    """P&L / Executive Summary input: each column's net movement; `movement` = the Total column."""
    out = []
    for row, _ in mtb.account_rows(ledger.accounts, snapshot, overrides):
        vals = {c.key: round(ledger.net(row["account_id"], c.start, c.end), 2) for c in cols}
        if _nonzero(vals):
            out.append({**row, **vals, "movement": vals.get(TOTAL, 0.0)})
    return out


def _balance_rows(ledger: mtb.Ledger, snapshot: dict[str, Any], overrides: dict[str, dict[str, str]],
                  cols: list[periods.Col]) -> list[dict[str, Any]]:
    """Balance Sheet input: each account's balance at each column's end (P&L since that fiscal year)."""
    out, pl_accounts = [], []
    for row, is_pl in mtb.account_rows(ledger.accounts, snapshot, overrides):
        acc = row["account_id"]
        if is_pl:
            pl_accounts.append(acc)
        bal = {c.key: round(ledger.balance(acc, c.end + mtb.DAY, ledger.fy(c.end), is_pl), 2) for c in cols}
        if _nonzero(bal):
            out.append({**row, "balances": bal})
    retained = {c.key: round(ledger.retained(pl_accounts, ledger.fy(c.end)), 2) for c in cols}
    if _nonzero(retained):
        out.append({**mtb.retained_row(), "balances": retained})
    return out


def build_statement(name: str, cols: list[periods.Col], snapshot: dict[str, Any],
                    overrides: dict[str, dict[str, str]], *, refresh: bool = False,
                    cache: GLCache | None = None) -> tuple[Statement, dict[str, Any]]:
    """→ (Statement with one column per `cols` key, fetch meta). BS columns are balances at each end."""
    if name not in STATEMENTS:
        raise ValueError(f"name must be one of {sorted(STATEMENTS)}")
    ledger, meta = _ledger(cols, snapshot, refresh, cache)
    main = [c for c in cols if c.key != TOTAL and not _COMPARE.match(c.key)] or cols
    start, end = periods.span(main)
    summary: dict[str, Any] = {
        "from_date": start.isoformat(), "to_date": end.isoformat(),
        "currency_code": snapshot.get("currency_code", ""),
        "organization_name": snapshot.get("organization_name", ""),
    }
    if name == "BS":
        summary.update(months=[c.key for c in cols], as_at="each column's end")
        stmt = build_balance_sheet(_balance_rows(ledger, snapshot, overrides, cols), summary)
    else:
        summary["months"] = [c.key for c in cols if c.key != TOTAL]
        pl, figures = build_profit_and_loss(_flow_rows(ledger, snapshot, overrides, cols), summary)
        stmt = pl if name == "PL" else build_executive_summary(figures, summary)
    stmt.columns = [c.key for c in cols]
    return stmt, meta


def statement(name: str, cols: list[periods.Col], snapshot: dict[str, Any],
              overrides: dict[str, dict[str, str]], *, refresh: bool = False,
              cache: GLCache | None = None) -> dict[str, Any]:
    """The `/api/statement` payload: same shape as a stored run's, plus fetch meta."""
    stmt, meta = build_statement(name, cols, snapshot, overrides, refresh=refresh, cache=cache)
    keys = set(stmt.columns)
    return {
        "statement": name,
        "subtitle": stmt.subtitle,
        "columns": stmt.columns,
        "lines": [{"label": ln.label, "kind": ln.kind, "values": {k: v for k, v in ln.values.items() if k in keys}}
                  for ln in stmt.lines],
        "tree": [n.as_dict() for n in stmt.tree],
        **meta,
    }
