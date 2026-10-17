"""Trial balance with opening / closing balances and Category Master columns, over any columns.

Zoho's `/reports/generalledger` returns *period movement only* (balance ==
debit_total - credit_total for the range), so balances are assembled here. The
wanted columns (months, weeks, quarters, comparison periods…) are cut into
segments at every column start / end and fiscal-year start; one GL call per
segment plus one for everything before the first fiscal year:

    opening   = cumulative GL movement before the first column
    column_i  = Σ segments inside column i
    closing   = opening + Σ segments of the range

All amounts are signed debit-positive (Dr +, Cr −).

P&L accounts reset every financial year: their balance at any date only counts
movement since the start of that date's financial year. Earlier years' P&L
(net) is carried as one synthetic row, "Prior years P&L (retained)", mapped to
Reserves and surplus — so Σ opening and Σ closing are still zero.

The P&L / Balance Sheet reports group these rows by `pl_bs` / `category`.
`generate_monthly_trial_balance` is the CLI's one-shot fetch; `reports.live_financials`
reuses `segments` / `Ledger` / `account_rows` behind a cache.
"""

from __future__ import annotations

from bisect import bisect_left
from datetime import date, timedelta
from typing import Any, Callable, Iterable

from reports import category_master as cm
from reports.trial_balance import fetch_general_ledger
from zoho_client import ZohoClient

BOOKS_EPOCH = date(2000, 1, 1)  # earlier than any Zoho posting
RETAINED_ID = "__prior_years_pl__"
RETAINED_NAME = "Prior years P&L (retained)"
DAY = timedelta(days=1)

Moves = dict[str, tuple[float, float]]  # account_id → (debit_total, credit_total)

BASE_COLUMNS = [
    "account_code",
    "account_name",
    "account_type",
    "account_id",
    "parent_account_name",
    "group_ledger",
    "pl_bs",
    "category",
    "sub_category",
    "category_source",
    "opening",
]
TAIL_COLUMNS = ["period_debit", "period_credit", "movement", "closing", "closing_debit", "closing_credit"]


def month_ranges(from_date: date, to_date: date) -> list[tuple[str, date, date]]:
    """[(label 'YYYY-MM', start, end), …] clipped to [from_date, to_date]."""
    out = []
    cur = from_date
    while cur <= to_date:
        nxt = date(cur.year + (cur.month == 12), cur.month % 12 + 1, 1)
        end = min(nxt - DAY, to_date)
        out.append((cur.strftime("%Y-%m"), cur, end))
        cur = nxt
    return out


def fiscal_year_start(d: date, fy_start_month: int) -> date:
    year = d.year if d.month >= fy_start_month else d.year - 1
    return date(year, fy_start_month, 1)


def _f(val: Any) -> float:
    try:
        return float(val or 0)
    except (TypeError, ValueError):
        return 0.0


def _movement(client: ZohoClient, start: date, end: date) -> Moves:
    """account_id → (debit_total, credit_total) for [start, end]; empty if start > end."""
    if start > end:
        return {}
    out: Moves = {}
    for gl in fetch_general_ledger(client, start.isoformat(), end.isoformat()):
        account_id = str(gl.get("account_id") or "")
        if not account_id:
            continue
        dr, cr = out.get(account_id, (0.0, 0.0))
        out[account_id] = (dr + _f(gl.get("debit_total")), cr + _f(gl.get("credit_total")))
    return out


def segments(ranges: Iterable[tuple[date, date]], fy_start_month: int) -> list[tuple[date, date]]:
    """GL periods to fetch for these ranges: from the start of the first one's fiscal year to the last
    end, cut at every range start / end and fiscal-year start. The opening is BOOKS_EPOCH → first − 1."""
    ranges = list(ranges)
    if not ranges or any(a > b for a, b in ranges):
        raise ValueError("ranges must be non-empty, each with start <= end")
    lo, hi = min(a for a, _ in ranges), max(b for _, b in ranges)
    first = fiscal_year_start(lo, fy_start_month)
    cuts = {first, hi + DAY}
    for a, b in ranges:
        cuts |= {a, b + DAY}
    fy = date(first.year + 1, first.month, 1)
    while fy <= hi:
        cuts.add(fy)
        fy = date(fy.year + 1, fy.month, 1)
    ordered = sorted(cuts)
    return [(a, b - DAY) for a, b in zip(ordered, ordered[1:])]


class Ledger:
    """GL movement over consecutive `segments` plus everything before them (`opening`).

    Dates passed to the methods must be segment boundaries (a segment start, or the day after the last).
    """

    def __init__(self, segs: list[tuple[date, date]], opening: Moves, moves: list[Moves], fy_start_month: int):
        if not segs or len(segs) != len(moves):
            raise ValueError("one Moves per segment")
        self.fy_start_month = fy_start_month
        self.starts = [a for a, _ in segs]
        self.end = segs[-1][1] + DAY
        self.pre = dict(opening)
        self.accounts = set(opening).union(*moves)
        # Running debit / credit totals per account: index i = sum of segments before i.
        self.dr: dict[str, list[float]] = {}
        self.cr: dict[str, list[float]] = {}
        for acc in self.accounts:
            dr, cr = [0.0] * (len(segs) + 1), [0.0] * (len(segs) + 1)
            for i, m in enumerate(moves):
                d, c = m.get(acc, (0.0, 0.0))
                dr[i + 1], cr[i + 1] = dr[i] + d, cr[i] + c
            self.dr[acc], self.cr[acc] = dr, cr

    def _at(self, d: date) -> int:
        if d == self.end:
            return len(self.starts)
        i = bisect_left(self.starts, d)
        if i == len(self.starts) or self.starts[i] != d:
            raise ValueError(f"{d} is not a segment boundary")
        return i

    def fy(self, d: date) -> date:
        return fiscal_year_start(d, self.fy_start_month)

    def period(self, acc: str, a: date, b: date) -> tuple[float, float]:
        """(debit, credit) of [a, b]."""
        i, j = self._at(a), self._at(b + DAY)
        dr, cr = self.dr.get(acc), self.cr.get(acc)
        return (dr[j] - dr[i], cr[j] - cr[i]) if dr and cr else (0.0, 0.0)

    def net(self, acc: str, a: date, b: date) -> float:
        dr, cr = self.period(acc, a, b)
        return dr - cr

    def _cum(self, acc: str, d: date) -> float:
        """Net movement from BOOKS_EPOCH to the day before d."""
        pdr, pcr = self.pre.get(acc, (0.0, 0.0))
        dr, cr = self.dr.get(acc), self.cr.get(acc)
        i = self._at(d)
        return pdr - pcr + (dr[i] - cr[i] if dr and cr else 0.0)

    def balance(self, acc: str, upto: date, fy_from: date, is_pl: bool) -> float:
        """Balance before day `upto`; a P&L account only counts movement since `fy_from`."""
        return self._cum(acc, upto) - (self._cum(acc, fy_from) if is_pl else 0.0)

    def retained(self, pl_accounts: Iterable[str], fy_from: date) -> float:
        """P&L (net) before `fy_from`: the prior years' row."""
        return sum(self._cum(acc, fy_from) for acc in pl_accounts)


def fetch_ledger(
    fetch: Callable[[date, date], Moves],
    ranges: Iterable[tuple[date, date]],
    fy_start_month: int,
    log: Callable[[str], None] = print,
) -> Ledger:
    """One GL fetch for the opening + one per segment (no cache)."""
    segs = segments(ranges, fy_start_month)
    log(f"Opening balances: GL {BOOKS_EPOCH} → {segs[0][0] - DAY}…")
    opening = fetch(BOOKS_EPOCH, segs[0][0] - DAY)
    moves = []
    for a, b in segs:
        log(f"  GL {a} → {b}…")
        moves.append(fetch(a, b))
    return Ledger(segs, opening, moves, fy_start_month)


def account_rows(
    account_ids: Iterable[str],
    snapshot: dict[str, Any],
    overrides: dict[str, dict[str, str]],
) -> list[tuple[dict[str, Any], bool]]:
    """[(row of account + Category Master columns, is_pl)], no amounts yet."""
    categories = {r["account_id"]: r for r in cm.build_category_master(snapshot, overrides)}
    coa = {str(a["account_id"]): a for a in snapshot.get("accounts") or [] if a.get("account_id")}
    out = []
    for account_id in account_ids:
        cat = categories.get(account_id) or {}
        acc = coa.get(account_id) or {}
        is_pl = cat.get("pl_bs") == cm.PL if cat else (acc.get("account_type") in cm.PL_TYPES)
        row = {
            "account_code": acc.get("account_code") or cat.get("account_code") or "",
            "account_name": acc.get("account_name") or cat.get("ledger_name") or account_id,
            "account_type": acc.get("account_type") or "",
            "account_id": account_id,
            "parent_account_name": acc.get("parent_account_name") or "",
            "group_ledger": cat.get("group_ledger", ""),
            "pl_bs": cat.get("pl_bs", cm.PL if is_pl else cm.BS),
            "category": cat.get("category", ""),
            "sub_category": cat.get("sub_category", ""),
            "category_source": cat.get("source", "review"),
        }
        out.append((row, is_pl))
    return out


def retained_row() -> dict[str, Any]:
    return {
        "account_code": "",
        "account_name": RETAINED_NAME,
        "account_type": "equity",
        "account_id": RETAINED_ID,
        "parent_account_name": "",
        "group_ledger": "Ledger",
        "pl_bs": cm.BS,
        "category": "Reserves and surplus",
        "sub_category": "Retained earning",
        "category_source": "rule",
    }


def sort_rows(rows: list[dict[str, Any]]) -> None:
    rows.sort(key=lambda r: (r["pl_bs"] != cm.BS, r["account_code"] or "zzzz", r["account_name"].lower()))


def tb_rows(
    ledger: Ledger,
    snapshot: dict[str, Any],
    overrides: dict[str, dict[str, str]],
    cols: list[tuple[str, date, date]],
    *,
    include_zero: bool = False,
) -> list[dict[str, Any]]:
    """Trial balance over the span of `cols` [(key, start, end)]: opening, one net per column, closing."""
    lo, hi = min(a for _, a, _ in cols), max(b for _, _, b in cols)
    fy_from = ledger.fy(lo)
    ids = set(ledger.accounts)
    if include_zero:
        ids |= {str(a["account_id"]) for a in snapshot.get("accounts") or [] if a.get("account_id")}

    rows: list[dict[str, Any]] = []
    pl_accounts = []
    for row, is_pl in account_rows(ids, snapshot, overrides):
        acc = row["account_id"]
        if is_pl:
            pl_accounts.append(acc)
        opening = ledger.balance(acc, lo, fy_from, is_pl)
        row["opening"] = round(opening, 2)
        for key, a, b in cols:
            row[key] = round(ledger.net(acc, a, b), 2)
        _finish(row, opening, *ledger.period(acc, lo, hi))
        if include_zero or any(abs(row[k]) >= 0.005 for k in ("opening", "period_debit", "period_credit")):
            rows.append(row)

    prior_years_pl = ledger.retained(pl_accounts, fy_from)
    if abs(prior_years_pl) >= 0.005:
        row = {**retained_row(), "opening": round(prior_years_pl, 2)}
        for key, _, _ in cols:
            row[key] = 0.0
        _finish(row, prior_years_pl, 0.0, 0.0)
        rows.append(row)
    sort_rows(rows)
    return rows


def generate_monthly_trial_balance(
    client: ZohoClient,
    snapshot: dict[str, Any],
    overrides: dict[str, dict[str, str]],
    from_date: date,
    to_date: date,
    *,
    fy_start_month: int,
    include_zero: bool = False,
) -> tuple[list[dict[str, Any]], list[str], dict[str, Any]]:
    """→ (rows, columns, summary)."""
    if from_date > to_date:
        raise ValueError("from_date must be on or before to_date")

    months = month_ranges(from_date, to_date)
    ledger = fetch_ledger(lambda a, b: _movement(client, a, b), [(a, b) for _, a, b in months], fy_start_month)
    rows = tb_rows(ledger, snapshot, overrides, months, include_zero=include_zero)

    month_labels = [label for label, _, _ in months]
    columns = BASE_COLUMNS + month_labels + TAIL_COLUMNS
    summary = _summary(rows, month_labels)
    summary.update(
        {
            "organization_id": client.org_id,
            "organization_name": snapshot.get("organization_name", ""),
            "currency_code": snapshot.get("currency_code", ""),
            "from_date": from_date.isoformat(),
            "to_date": to_date.isoformat(),
            "fiscal_year_start": fiscal_year_start(from_date, fy_start_month).isoformat(),
            "months": month_labels,
            "sign": "debit positive (Dr +, Cr -)",
            "source": "GET /reports/generalledger (per month + opening) + GET /chartofaccounts",
        }
    )
    return rows, columns, summary


def _finish(row: dict[str, Any], opening: float, period_dr: float, period_cr: float) -> None:
    movement = period_dr - period_cr
    closing = opening + movement
    row.update(
        {
            "period_debit": round(period_dr, 2),
            "period_credit": round(period_cr, 2),
            "movement": round(movement, 2),
            "closing": round(closing, 2),
            "closing_debit": round(closing, 2) if closing > 0 else 0.0,
            "closing_credit": round(-closing, 2) if closing < 0 else 0.0,
        }
    )


def _summary(rows: list[dict[str, Any]], month_labels: list[str]) -> dict[str, Any]:
    def total(key: str) -> float:
        return round(sum(r.get(key, 0.0) for r in rows), 2)

    return {
        "account_count": len(rows),
        "opening_net": total("opening"),
        "months_net": {m: total(m) for m in month_labels},
        "period_debit": total("period_debit"),
        "period_credit": total("period_credit"),
        "closing_debit": total("closing_debit"),
        "closing_credit": total("closing_credit"),
        "closing_net": total("closing"),
        "uncategorised": sum(1 for r in rows if not r["category"]),
        "needs_review": sum(1 for r in rows if r["category_source"] == "review"),
    }
