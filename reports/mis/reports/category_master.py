"""Category Master built from Zoho Books Chart of Accounts.

Maps every ledger to the MIS reporting lines used by the P&L / Balance Sheet /
Executive Summary in `report-template.xlsx`:

    Ledger Name | Entity Name | Concate | Group/Ledger | PL/BS | Category | Sub Category

Resolution order for each account (first hit wins):

1. `category_overrides.csv` (hand-edited, keyed by account_id)
2. NAME_PATTERN_RULES on the account's own name (e.g. "Profit Share *").
3. ANCESTOR_RULES — walk from the account itself up its parent chain; the
   nearest ancestor (or self) with a rule decides.
4. TYPE_RULES — fallback on Zoho `account_type`.
5. Otherwise flagged REVIEW.

`source` on each row tells which step decided: override | rule | type | review.
Rules marked `review=True` still suggest a category but flag the row for a
human to confirm (judgement calls such as investor profit shares).

Sub Category, unless a rule fixes it, is the account's ancestor directly below
the matched rule node (e.g. `Food exp-Arun` under rule `Personnel Expenses`
→ `Food Expenses - Staff`), or the account's own name when it is that node or
its direct child.
"""

from __future__ import annotations

import csv
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from zoho_client import ZohoClient

COLUMNS = [
    "account_id",
    "account_code",
    "ledger_name",
    "entity_name",
    "concate",
    "group_ledger",
    "pl_bs",
    "category",
    "sub_category",
    "source",
    "note",
    "account_type",
    "parent_account_name",
    "path",
    "current_balance",
    "is_active",
]

OVERRIDE_COLUMNS = ["account_id", "ledger_name", "pl_bs", "category", "sub_category", "note"]

PL = "PL"
BS = "BS"

PL_TYPES = {"income", "other_income", "expense", "other_expense", "cost_of_goods_sold"}


@dataclass(frozen=True)
class Rule:
    pl_bs: str
    category: str
    sub_category: str | None = None  # None → derive from path
    review: bool = False
    note: str = ""


# Keyed by Zoho account name (case-insensitive). Nearest match up the tree wins,
# so a specific child rule (e.g. "IT & Software Exp") beats its parent's rule.
ANCESTOR_RULES: dict[str, Rule] = {
    # ---------------- P&L: revenue ----------------
    "Revenue": Rule(PL, "Revenue Booked"),
    "Discount": Rule(PL, "Revenue Booked", "Discounts & Rebates"),
    "Rebate": Rule(PL, "Revenue Booked", "Discounts & Rebates"),
    "Shipping Charge": Rule(PL, "Direct Income"),
    "Other Charges": Rule(PL, "Direct Income"),
    "Other Revenue": Rule(PL, "Indirect Income"),
    "Late Fee Income": Rule(PL, "Indirect Income"),
    "Roundoff": Rule(PL, "Indirect Income"),
    # ---------------- P&L: cost of sales ----------------
    "Cost of Sales": Rule(PL, "COGS"),
    "Cost of Sales - Other Revenue": Rule(PL, "COGS"),
    "Purchase Discounts": Rule(PL, "COGS", "Purchase Discounts"),
    "Direct Expenses": Rule(PL, "Direct Expenses"),
    # ---------------- P&L: operating expenses ----------------
    "Personnel Expenses": Rule(PL, "Employee Costs"),
    "Salaries And Employee Wages Expense": Rule(PL, "Employee Costs", "Salary and Allowances"),
    "Gratuity Expense": Rule(PL, "Employee Costs", "Gratuity"),
    "Air Travel Allowance Expense": Rule(PL, "Employee Costs", "Leave Tickets"),
    "Office and General Expenses": Rule(PL, "Office Expenses"),
    "IT & Software Exp": Rule(PL, "Technical Expenses", "Software Expenses"),
    "Rent and Utilities Expenses": Rule(PL, "Office Expenses"),
    "Vehicle Expenses": Rule(PL, "Travelling & Conveyance", "Vehicle Expenses"),
    "Travel Expense (Business)": Rule(PL, "Travelling & Conveyance", "Travelling Expenses"),
    "Legal And Licensing Expenses": Rule(PL, "Rates and Taxes"),
    "Legal Charges": Rule(PL, "Legal & Professional Fees", "Legal Charges"),
    "Audit Fee": Rule(PL, "Legal & Professional Fees", "Audit Fees"),
    "Certification Expenses": Rule(PL, "Legal & Professional Fees", "Certification Expenses"),
    "Sales And Marketing Expenses": Rule(PL, "Selling & Distribution exp"),
    "Advertisement Expenses": Rule(PL, "Advertisement & Marketing Fees", "Advertisement Expenses"),
    "Sales Promotion Expenses": Rule(PL, "Advertisement & Marketing Fees", "Sales Promotion Expenses"),
    "Administrative Expenses": Rule(PL, "Other Expenses"),
    "Operating Expenses": Rule(PL, "Other Expenses"),
    "Other Expenses": Rule(PL, "Other Expenses"),
    "incorporation exp": Rule(PL, "Other Expenses", "Incorporation Expenses"),
    "Uncategorized": Rule(PL, "Other Expenses", "Uncategorized", review=True,
                          note="Zoho catch-all; reclassify postings"),
    "Munsif Related Party Exp": Rule(PL, "Other Expenses", "Related Party Expenses", review=True,
                                     note="Related-party expense; confirm treatment"),
    # ---------------- P&L: below EBITDA ----------------
    "Financial Expenses": Rule(PL, "Finance Cost"),
    "Bank Fees and Charges": Rule(PL, "Finance Cost", "Bank Charges"),
    "Depreciation Expenses": Rule(PL, "Depreciation", "Depreciation"),
    "Exchange Gain or Loss": Rule(PL, "FX Gain/loss", "FX Gain/loss"),
    "Bad Debt": Rule(PL, "Bad Debt/Provision for Loss", "Bad Debt"),
    "Bad Debt – Small Balance Write-offs": Rule(PL, "Bad Debt/Provision for Loss", "Bad Debt"),
    "Tax Expenses": Rule(PL, "Income Tax", "Corporate Tax"),
    # ---------------- BS: assets ----------------
    "Intagible Asset": Rule(BS, "Fixed assets -Intangible", "Fixed assets -Intangible"),
    "Preliminary Exp": Rule(BS, "Other Non-Current Asset", "Preliminary Expenses"),
    "Goods In Transit": Rule(BS, "Closing Stock", "Goods In Transit"),
    "Cash Sales Receivables": Rule(BS, "Trade Receivables", "Trade Receivables"),
    "Receivables": Rule(BS, "Trade Receivables"),
    "Due From Related Party": Rule(BS, "Other Current Asset", "Due From Related Party"),
    "Loans Receivables": Rule(BS, "Other Current Asset", "Loans Receivables"),
    "Accruals And Other Current Assets": Rule(BS, "Other Current Asset"),
    "Securities And Deposits": Rule(BS, "Other Current Asset", "Security Deposit"),
    "Employee Advance": Rule(BS, "Other Current Asset", "Employee Advance"),
    "Salary Advances": Rule(BS, "Other Current Asset", "Employee Advance"),
    "Staff Loans": Rule(BS, "Other Current Asset", "Employee Advance"),
    "Loan Account - Munsif": Rule(BS, "Other Current Asset", "Related Party Advances", review=True,
                                  note="Partner loan account; confirm asset vs equity"),
    "Munsif Personal (Meat Transactions individual)": Rule(
        BS, "Other Current Asset", "Related Party Advances", review=True,
        note="Partner personal transactions; confirm asset vs equity"),
    "Input VAT": Rule(BS, "Other Current Asset", "VAT Input"),
    "Input Excise Tax": Rule(BS, "Other Current Asset", "VAT Input"),
    # ---------------- BS: liabilities ----------------
    "Payables": Rule(BS, "Provisions and Other Current Liabilities"),
    "Trade Payables": Rule(BS, "Trade payables", "Trade payables"),
    "Unearned Revenue": Rule(BS, "Advance from customer", "Advance from customer"),
    "VAT": Rule(BS, "Statutory Dues", "VAT Payable"),
    "Output VAT": Rule(BS, "Statutory Dues", "VAT Payable"),
    "VAT Payable": Rule(BS, "Statutory Dues", "VAT Payable"),
    "GCC VAT Payable": Rule(BS, "Statutory Dues", "VAT Payable"),
    "Excise Tax Payable": Rule(BS, "Statutory Dues", "Excise Tax Payable"),
    "Output Excise Tax": Rule(BS, "Statutory Dues", "Excise Tax Payable"),
    "Statutory Deductions Payable": Rule(BS, "Statutory Dues", "Statutory Deductions"),
    "Deductions Payable": Rule(BS, "Statutory Dues", "Statutory Deductions"),
    "Financial Liabilities": Rule(BS, "Short-term borrowings"),  # sub refined by _borrowing_sub
    "Net Salary Payable": Rule(BS, "Provisions and Other Current Liabilities", "Salary Payable"),
    "Hold Salary Payable": Rule(BS, "Provisions and Other Current Liabilities", "Salary Payable"),
    "Salary Payables": Rule(BS, "Provisions and Other Current Liabilities", "Salary Payable"),
    "Reimbursements Payable": Rule(BS, "Provisions and Other Current Liabilities", "Employee Reimbursements"),
    "Accruals And Other Liabilities": Rule(BS, "Provisions and Other Current Liabilities"),
    "Provisions (Contingencies)": Rule(BS, "Provisions and Other Current Liabilities", "Provision Payable"),
    "Inter Branch Account": Rule(BS, "Provisions and Other Current Liabilities", "Inter Branch Account",
                                 review=True, note="Inter-branch balance; should net to zero"),
    "Opening Balance Adjustments": Rule(BS, "Provisions and Other Current Liabilities",
                                        "Opening Balance Adjustments", review=True,
                                        note="Zoho migration suspense; should be zero"),
    "Tag Adjustments": Rule(BS, "Provisions and Other Current Liabilities", "Tag Adjustments",
                            review=True, note="Zoho system account; confirm treatment"),
    "Gratuity Payable": Rule(BS, "Long-term provisions", "Gratuity Payable"),
    "EOSB Payable": Rule(BS, "Long-term provisions", "Gratuity Payable"),
    "Air Travel Allowance Payable": Rule(BS, "Long-term provisions", "Leave Ticket Payable"),
    # ---------------- BS: equity ----------------
    "Share Capital": Rule(BS, "Share Capital", "Equity Share Capital"),
    "Retained Earnings": Rule(BS, "Reserves and surplus", "Retained earning"),
    "Opening Balance Offset": Rule(BS, "Reserves and surplus", "Opening Balance Offset", review=True,
                                   note="Zoho migration suspense; should be zero"),
    "Owners Equity": Rule(BS, "Partners Capital & Current Accounts"),
}

# Checked against the account's own name before the ancestor walk.
NAME_PATTERN_RULES: list[tuple[re.Pattern[str], Rule]] = [
    (re.compile(r"^profit share", re.IGNORECASE),
     Rule(PL, "Finance Cost", "Profit Share to Investors", review=True,
          note="Profit paid on short-term investor funds; confirm Finance Cost vs appropriation")),
    (re.compile(r"^loan profit", re.IGNORECASE), Rule(PL, "Finance Cost", "Loan Profit")),
]

# Fallback by Zoho account_type → (PL/BS, Category, Sub Category or None).
TYPE_RULES: dict[str, tuple[str, str, str | None]] = {
    "income": (PL, "Revenue Booked", None),
    "other_income": (PL, "Indirect Income", None),
    "cost_of_goods_sold": (PL, "Direct Expenses", None),
    "expense": (PL, "Other Expenses", None),
    "other_expense": (PL, "Other Expenses", None),
    "bank": (BS, "Cash and bank balances", "Bank Balance"),
    "cash": (BS, "Cash and bank balances", "Cash Balance"),
    "accounts_receivable": (BS, "Trade Receivables", "Trade Receivables"),
    "accounts_payable": (BS, "Trade payables", "Trade payables"),
    "stock": (BS, "Closing Stock", "Closing Stock"),
    "fixed_asset": (BS, "Fixed assets -Tangible", "Fixed assets -Tangible"),
    "other_current_asset": (BS, "Other Current Asset", None),
    "other_asset": (BS, "Other Non-Current Asset", None),
    "other_current_liability": (BS, "Provisions and Other Current Liabilities", None),
    "long_term_liability": (BS, "Long-term borrowings", None),
    "other_liability": (BS, "Provisions and Other Current Liabilities", None),
    "equity": (BS, "Reserves and surplus", None),
}

# Reporting-line order for the editor dropdown (template PL/BS order first).
CATEGORIES: dict[str, list[str]] = {
    PL: [
        "Revenue Booked", "Direct Income", "COGS", "Direct Expenses", "Indirect Income",
        "Employee Costs", "Technical Expenses", "Selling & Distribution exp", "Office Expenses",
        "Advertisement & Marketing Fees", "Legal & Professional Fees", "Rates and Taxes",
        "Travelling & Conveyance", "Other Expenses", "Bad Debt/Provision for Loss",
        "Finance Cost", "Depreciation", "FX Gain/loss", "Income Tax",
    ],
    BS: [
        "Fixed assets -Tangible", "Fixed assets -Intangible", "Other Non-Current Asset",
        "Cash and bank balances", "Closing Stock", "Trade Receivables", "Other Current Asset",
        "Term Deposits", "Trade payables", "Advance from customer", "Statutory Dues",
        "Provisions and Other Current Liabilities", "Short-term borrowings", "Long-term borrowings",
        "Long-term provisions", "Share Capital", "Partners Capital & Current Accounts",
        "Reserves and surplus",
    ],
}

_BANK_LENDER = re.compile(r"\b(bank|wio|cbd|comfi|commercial bank)\b", re.IGNORECASE)
_INVESTOR = re.compile(r"\binvest", re.IGNORECASE)
_ACCU_DEP = re.compile(r"^accu\.?\s*dep", re.IGNORECASE)


def _borrowing_sub(name: str) -> str:
    if _BANK_LENDER.search(name):
        return "Bank and NBFC Borrowings"
    if _INVESTOR.search(name):
        return "Short-term Investor Funds"
    return "Unsecured Loan"


# ---------------------------------------------------------------------------
# Data access
# ---------------------------------------------------------------------------


def fetch_organization(client: ZohoClient) -> dict[str, Any]:
    """The configured organization's profile (name, currency, fiscal year...) from GET /organizations."""
    orgs = client.get("/organizations").get("organizations") or []
    org = next((o for o in orgs if str(o.get("organization_id")) == str(client.org_id)), None)
    if org is None:
        raise RuntimeError(f"organization {client.org_id} not in the /organizations response")
    return org


def fetch_coa_snapshot(client: ZohoClient) -> dict[str, Any]:
    """Chart of accounts + organization name, ready to cache as JSON."""
    accounts = client.get("/chartofaccounts", {"showbalance": "true"}).get("chartofaccounts") or []
    orgs = client.get("/organizations").get("organizations") or []
    org = next((o for o in orgs if str(o.get("organization_id")) == str(client.org_id)), {})
    return {
        "organization_id": client.org_id,
        "organization_name": org.get("name") or client.org_id,
        "currency_code": org.get("currency_code") or "",
        "fiscal_year_start_month": _fy_start_month(org.get("fiscal_year_start_month")),
        "accounts": accounts,
    }


_MONTHS = ["january", "february", "march", "april", "may", "june", "july", "august",
           "september", "october", "november", "december"]


def _fy_start_month(raw: Any) -> int | None:
    """Zoho returns 0-based month numbers on read (0 = January) but names on write."""
    if raw is None or raw == "":
        return None
    text = str(raw).strip().lower()
    if text in _MONTHS:
        return _MONTHS.index(text) + 1
    try:
        n = int(float(text))
    except ValueError:
        return None
    return n + 1 if 0 <= n <= 11 else None


def load_overrides(path: Path) -> dict[str, dict[str, str]]:
    if not path.exists():
        return {}
    with path.open(newline="", encoding="utf-8") as f:
        return {
            r["account_id"].strip(): {k: (r.get(k) or "").strip() for k in OVERRIDE_COLUMNS}
            for r in csv.DictReader(f)
            if (r.get("account_id") or "").strip()
        }


def save_overrides(path: Path, overrides: dict[str, dict[str, str]]) -> None:
    rows = sorted(overrides.values(), key=lambda r: r.get("ledger_name", "").lower())
    tmp = path.with_suffix(".tmp")
    with tmp.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=OVERRIDE_COLUMNS, extrasaction="ignore")
        writer.writeheader()
        for r in rows:
            writer.writerow({c: r.get(c, "") for c in OVERRIDE_COLUMNS})
    tmp.replace(path)


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

_RULES_BY_KEY = {k.lower(): (k, v) for k, v in ANCESTOR_RULES.items()}


def _chain(account: dict[str, Any], by_id: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    """[self, parent, grandparent, …] — guarded against cycles."""
    out, seen, cur = [], set(), account
    while cur and str(cur.get("account_id")) not in seen:
        seen.add(str(cur.get("account_id")))
        out.append(cur)
        cur = by_id.get(str(cur.get("parent_account_id") or ""))
    return out


def _classify(account: dict[str, Any], chain: list[dict[str, Any]]) -> tuple[str, str, str, str, str]:
    """→ (pl_bs, category, sub_category, source, note)."""
    name = account.get("account_name") or ""
    for pattern, rule in NAME_PATTERN_RULES:
        if pattern.search(name) and (rule.pl_bs == PL) == (account.get("account_type") in PL_TYPES):
            return rule.pl_bs, rule.category, rule.sub_category or name, \
                "review" if rule.review else "rule", rule.note or f"pattern: {pattern.pattern}"
    for i, node in enumerate(chain):
        hit = _RULES_BY_KEY.get((node.get("account_name") or "").strip().lower())
        if not hit:
            continue
        rule_name, rule = hit
        if rule.sub_category:
            sub = rule.sub_category
        elif rule.category == "Short-term borrowings":
            sub = _borrowing_sub(name)
        elif i <= 1:
            sub = name  # the rule node itself, or its direct child
        else:
            sub = chain[i - 1].get("account_name") or name  # child of the rule node on this path
        source = "review" if rule.review else "rule"
        note = rule.note or f"rule: {rule_name}"
        return rule.pl_bs, rule.category, sub, source, note

    atype = account.get("account_type") or ""
    if atype in TYPE_RULES:
        pl_bs, category, sub = TYPE_RULES[atype]
        if not sub:
            sub = chain[1].get("account_name") if len(chain) > 1 else name
        if atype == "fixed_asset" and _ACCU_DEP.match(name):
            sub = "Accumulated Depreciation"
        return pl_bs, category, sub, "type", f"type: {atype}"

    pl_bs = PL if atype in PL_TYPES else BS
    return pl_bs, "", "", "review", f"no rule for account_type '{atype}'"


def build_category_master(
    snapshot: dict[str, Any],
    overrides: dict[str, dict[str, str]] | None = None,
    *,
    include_inactive: bool = True,
) -> list[dict[str, Any]]:
    overrides = overrides or {}
    entity = snapshot.get("organization_name") or ""
    accounts = snapshot.get("accounts") or []
    by_id = {str(a["account_id"]): a for a in accounts if a.get("account_id")}
    parent_ids = {str(a.get("parent_account_id")) for a in accounts if a.get("parent_account_id")}

    rows: list[dict[str, Any]] = []
    for acc in accounts:
        if not include_inactive and not acc.get("is_active", True):
            continue
        account_id = str(acc.get("account_id") or "")
        name = (acc.get("account_name") or "").strip()
        chain = _chain(acc, by_id)
        pl_bs, category, sub, source, note = _classify(acc, chain)

        ov = overrides.get(account_id)
        if ov and (ov.get("category") or ov.get("pl_bs") or ov.get("sub_category")):
            pl_bs = ov.get("pl_bs") or pl_bs
            category = ov.get("category") or category
            sub = ov.get("sub_category") or sub
            source = "override"
            note = ov.get("note") or "manual override"

        rows.append(
            {
                "account_id": account_id,
                "account_code": acc.get("account_code") or "",
                "ledger_name": name,
                "entity_name": entity,
                "concate": f"{name}{entity}",
                "group_ledger": "Group" if account_id in parent_ids else "Ledger",
                "pl_bs": pl_bs,
                "category": category,
                "sub_category": sub,
                "source": source,
                "note": note,
                "account_type": acc.get("account_type") or "",
                "parent_account_name": acc.get("parent_account_name") or "",
                "path": " > ".join(n.get("account_name") or "" for n in reversed(chain)),
                "current_balance": round(float(acc.get("current_balance") or 0), 2),
                "is_active": bool(acc.get("is_active", True)),
            }
        )

    rows.sort(key=lambda r: (r["pl_bs"] != BS, r["path"].lower()))
    return rows


def category_master_summary(rows: list[dict[str, Any]]) -> dict[str, Any]:
    by_source: dict[str, int] = {}
    for r in rows:
        by_source[r["source"]] = by_source.get(r["source"], 0) + 1
    return {
        "account_count": len(rows),
        "ledger_count": sum(1 for r in rows if r["group_ledger"] == "Ledger"),
        "group_count": sum(1 for r in rows if r["group_ledger"] == "Group"),
        "by_source": by_source,
    }
