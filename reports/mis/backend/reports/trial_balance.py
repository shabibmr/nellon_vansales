"""Trial balance built from General Ledger + Chart of Accounts.

Zoho `/journals` only returns manual journal vouchers, so invoices/bills/expenses
would be missing. Period movements come from:

    GET /reports/generalledger
        ?filter_by=TransactionDate.CustomDate&from_date=&to_date=

Account metadata (type, parent, active flag) comes from:

    GET /chartofaccounts?showbalance=true

Each GL row already has period `debit_total`, `credit_total`, and net `balance`.
This module joins COA metadata and emits a flat trial-balance style sheet:

- gross period debit / credit (from GL)
- net debit / net credit columns (balance on one side only)
"""

from __future__ import annotations

from typing import Any

from common.zoho_client import ZohoClient

COLUMNS = [
    "account_code",
    "account_name",
    "account_type",
    "account_id",
    "parent_account_id",
    "parent_account_name",
    "is_active",
    "debit_total",
    "credit_total",
    "net_debit",
    "net_credit",
    "balance",
    "is_debit",
]


def fetch_chart_of_accounts(client: ZohoClient) -> dict[str, dict[str, Any]]:
    body = client.get("/chartofaccounts", {"showbalance": "true"})
    rows = body.get("chartofaccounts") or []
    return {str(a["account_id"]): a for a in rows if a.get("account_id")}


def fetch_general_ledger(client: ZohoClient, from_date: str, to_date: str) -> list[dict[str, Any]]:
    body = client.get(
        "/reports/generalledger",
        {
            "filter_by": "TransactionDate.CustomDate",
            "from_date": from_date,
            "to_date": to_date,
        },
        timeout=180,
    )
    return list(body.get("generalledger") or [])


def _f(val: Any) -> float:
    try:
        return float(val or 0)
    except (TypeError, ValueError):
        return 0.0


def build_trial_balance_rows(
    gl_rows: list[dict[str, Any]],
    coa_by_id: dict[str, dict[str, Any]],
    *,
    include_zero: bool = False,
) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for gl in gl_rows:
        account_id = str(gl.get("account_id") or "")
        debit = round(_f(gl.get("debit_total")), 2)
        credit = round(_f(gl.get("credit_total")), 2)
        balance = round(_f(gl.get("balance")), 2)
        if not include_zero and debit == 0 and credit == 0 and balance == 0:
            continue

        coa = coa_by_id.get(account_id) or {}
        is_debit = bool(gl.get("is_debit")) if "is_debit" in gl else balance >= 0
        # Net TB columns: put absolute balance on the natural side.
        if is_debit:
            net_debit, net_credit = abs(balance), 0.0
        else:
            net_debit, net_credit = 0.0, abs(balance)

        out.append(
            {
                "account_code": gl.get("account_code") or coa.get("account_code") or "",
                "account_name": gl.get("name") or coa.get("account_name") or "",
                "account_type": coa.get("account_type") or "",
                "account_id": account_id,
                "parent_account_id": str(coa.get("parent_account_id") or ""),
                "parent_account_name": coa.get("parent_account_name") or "",
                "is_active": coa.get("is_active", True),
                "debit_total": debit,
                "credit_total": credit,
                "net_debit": round(net_debit, 2),
                "net_credit": round(net_credit, 2),
                "balance": balance,
                "is_debit": is_debit,
            }
        )

    out.sort(key=lambda r: (r["account_code"] or "zzzz", r["account_name"]))
    return out


def trial_balance_summary(rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "account_count": len(rows),
        "debit_total_sum": round(sum(r["debit_total"] for r in rows), 2),
        "credit_total_sum": round(sum(r["credit_total"] for r in rows), 2),
        "net_debit_sum": round(sum(r["net_debit"] for r in rows), 2),
        "net_credit_sum": round(sum(r["net_credit"] for r in rows), 2),
    }


def generate_trial_balance(
    client: ZohoClient,
    from_date: str,
    to_date: str,
    *,
    include_zero: bool = False,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    print(f"Fetching chart of accounts…")
    coa = fetch_chart_of_accounts(client)
    print(f"  accounts in COA: {len(coa)}")
    print(f"Fetching general ledger {from_date} → {to_date}…")
    gl = fetch_general_ledger(client, from_date, to_date)
    print(f"  GL rows: {len(gl)}")
    rows = build_trial_balance_rows(gl, coa, include_zero=include_zero)
    summary = trial_balance_summary(rows)
    summary.update(
        {
            "from_date": from_date,
            "to_date": to_date,
            "source": "GET /reports/generalledger + GET /chartofaccounts",
            "organization_id": client.org_id,
        }
    )
    return rows, summary
