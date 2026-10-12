"""Monthly trial balance with opening / closing balances and Category Master columns.

Zoho's `/reports/generalledger` returns *period movement only* (balance ==
debit_total - credit_total for the range), so balances are assembled here:

    opening  = cumulative GL movement before `from_date`
    month_i  = GL movement for each calendar month (clipped to the range)
    closing  = opening + Σ months

All amounts are signed debit-positive (Dr +, Cr −).

P&L accounts reset every financial year: their opening only counts movement
since the start of the financial year that contains `from_date`. Earlier years'
P&L (net) is carried as one synthetic row, "Prior years P&L (retained)", mapped
to Reserves and surplus — so Σ opening and Σ closing are still zero.

The P&L / Balance Sheet reports group these rows by `pl_bs` / `category`.
"""

from __future__ import annotations

from datetime import date, timedelta
from typing import Any

from reports import category_master as cm
from reports.trial_balance import fetch_general_ledger
from zoho_client import ZohoClient

BOOKS_EPOCH = date(2000, 1, 1)  # earlier than any Zoho posting
RETAINED_ID = "__prior_years_pl__"
RETAINED_NAME = "Prior years P&L (retained)"

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
        end = min(nxt - timedelta(days=1), to_date)
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


def _movement(client: ZohoClient, start: date, end: date) -> dict[str, tuple[float, float]]:
    """account_id → (debit_total, credit_total) for [start, end]; empty if start > end."""
    if start > end:
        return {}
    out: dict[str, tuple[float, float]] = {}
    for gl in fetch_general_ledger(client, start.isoformat(), end.isoformat()):
        account_id = str(gl.get("account_id") or "")
        if not account_id:
            continue
        dr, cr = out.get(account_id, (0.0, 0.0))
        out[account_id] = (dr + _f(gl.get("debit_total")), cr + _f(gl.get("credit_total")))
    return out


def _net(pair: tuple[float, float] | None) -> float:
    return (pair[0] - pair[1]) if pair else 0.0


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

    categories = {r["account_id"]: r for r in cm.build_category_master(snapshot, overrides)}
    coa = {str(a["account_id"]): a for a in snapshot.get("accounts") or [] if a.get("account_id")}
    fy_start = fiscal_year_start(from_date, fy_start_month)
    day_before = from_date - timedelta(days=1)

    print(f"Opening balances: GL {BOOKS_EPOCH} → {day_before} (P&L since {fy_start})…")
    before_fy = _movement(client, BOOKS_EPOCH, min(fy_start - timedelta(days=1), day_before))
    fy_to_start = _movement(client, fy_start, day_before)

    months = month_ranges(from_date, to_date)
    month_moves: list[tuple[str, dict[str, tuple[float, float]]]] = []
    for label, start, end in months:
        print(f"  GL {label} ({start} → {end})…")
        month_moves.append((label, _movement(client, start, end)))

    account_ids = set(before_fy) | set(fy_to_start)
    for _, moves in month_moves:
        account_ids |= set(moves)
    if include_zero:
        account_ids |= set(coa)

    rows: list[dict[str, Any]] = []
    prior_years_pl = 0.0
    for account_id in account_ids:
        cat = categories.get(account_id) or {}
        acc = coa.get(account_id) or {}
        is_pl = cat.get("pl_bs") == cm.PL if cat else (acc.get("account_type") in cm.PL_TYPES)

        if is_pl:
            prior_years_pl += _net(before_fy.get(account_id))
            opening = _net(fy_to_start.get(account_id))
        else:
            opening = _net(before_fy.get(account_id)) + _net(fy_to_start.get(account_id))

        row: dict[str, Any] = {
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
            "opening": round(opening, 2),
        }
        period_dr = period_cr = 0.0
        for label, moves in month_moves:
            dr, cr = moves.get(account_id, (0.0, 0.0))
            period_dr += dr
            period_cr += cr
            row[label] = round(dr - cr, 2)
        _finish(row, opening, period_dr, period_cr)
        if include_zero or any(abs(row[k]) >= 0.005 for k in ("opening", "period_debit", "period_credit")):
            rows.append(row)

    if abs(prior_years_pl) >= 0.005:
        row = {
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
            "opening": round(prior_years_pl, 2),
        }
        for label, _ in month_moves:
            row[label] = 0.0
        _finish(row, prior_years_pl, 0.0, 0.0)
        rows.append(row)

    rows.sort(key=lambda r: (r["pl_bs"] != cm.BS, r["account_code"] or "zzzz", r["account_name"].lower()))
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
            "fiscal_year_start": fy_start.isoformat(),
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
