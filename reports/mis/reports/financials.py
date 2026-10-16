"""P&L, Balance Sheet and Executive Summary from monthly trial balance rows.

Pure functions — no Zoho calls. Input is the `rows` / `summary` produced by
`reports.monthly_trial_balance.generate_monthly_trial_balance` (or loaded back
from its JSON), so statements can be rebuilt offline from a saved TB.

TB amounts are signed debit-positive. Statements flip signs for display:

- P&L: income lines (Revenue, Direct Income, Indirect Income, FX gain) shown
  credit-positive; cost lines shown debit-positive.
- BS: assets debit-positive; liabilities and equity credit-positive.

Each statement is a list of `Line`s; `values` maps column label → amount
(P&L: one column per month + "Total"; BS: one column per month end).

The P&L and Executive Summary also carry a `tree` of `Node`s for the web
viewer's expandable rows: section → category → sub-category → account. The
flat `lines` stay the source for the stored statement and the Excel export.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Iterable

from reports import category_master as cm

TOTAL = "Total"

# ---------------------------------------------------------------------------
# P&L structure (category names match reports.category_master)
# ---------------------------------------------------------------------------

REVENUE_CATS = ["Revenue Booked", "Direct Income"]
COGS_CATS = ["COGS"]
DIRECT_EXP_CATS = ["Direct Expenses"]
OTHER_INCOME_CATS = ["Indirect Income"]
FIXED_EXP_CATS = [
    "Employee Costs", "Technical Expenses", "Selling & Distribution exp", "Office Expenses",
    "Advertisement & Marketing Fees", "Legal & Professional Fees", "Rates and Taxes",
    "Travelling & Conveyance", "Other Expenses", "Bad Debt/Provision for Loss",
]
FINANCE_CATS = ["Finance Cost"]
DEPRECIATION_CATS = ["Depreciation"]
FX_CATS = ["FX Gain/loss"]
TAX_CATS = ["Income Tax"]
UNMAPPED_PL = "Unmapped P&L accounts"

# Shown credit-positive (income / gains).
CREDIT_POSITIVE_PL = set(REVENUE_CATS + OTHER_INCOME_CATS + FX_CATS)

# ---------------------------------------------------------------------------
# Balance sheet structure
# ---------------------------------------------------------------------------

ASSET_CATS = [
    "Fixed assets -Tangible", "Fixed assets -Intangible", "Other Non-Current Asset",
    "Cash and bank balances", "Closing Stock", "Trade Receivables", "Other Current Asset",
    "Term Deposits",
]
LIABILITY_CATS = [
    "Trade payables", "Advance from customer", "Statutory Dues",
    "Provisions and Other Current Liabilities", "Short-term borrowings", "Long-term borrowings",
    "Long-term provisions",
]
EQUITY_CATS = ["Share Capital", "Partners Capital & Current Accounts", "Reserves and surplus"]
CURRENT_YEAR_EARNINGS = "Current Year Earnings"
UNMAPPED_ASSETS = "Unmapped asset accounts"
UNMAPPED_LIABILITIES = "Unmapped liability / equity accounts"

ASSET_TYPES = {
    "bank", "cash", "accounts_receivable", "stock", "fixed_asset", "other_current_asset", "other_asset",
}


_MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


def _period_label(summary: dict[str, Any]) -> str:
    """'Apr-26 – Sep-26' (one month when both ends fall in it)."""
    def mon(iso: Any) -> str:
        s = str(iso)
        return f"{_MON[int(s[5:7]) - 1]}-{s[2:4]}"
    a, b = mon(summary.get("from_date")), mon(summary.get("to_date"))
    return a if a == b else f"{a} – {b}"


@dataclass
class Line:
    label: str
    kind: str  # title | category | sub | total | pct | check | blank
    values: dict[str, float] = field(default_factory=dict)

    def as_row(self, columns: list[str]) -> dict[str, Any]:
        row: dict[str, Any] = {"line": self.label, "kind": self.kind}
        for c in columns:
            row[c] = self.values.get(c, "" if self.kind in ("title", "blank") else 0.0)
        return row


@dataclass
class Node:
    """One row of the expandable statement: its values are the sum of its children's."""

    label: str
    kind: str  # section | category | sub | account | total | pct
    values: dict[str, float] = field(default_factory=dict)
    children: list[Node] = field(default_factory=list)
    meta: str = ""  # account code on account rows

    def as_dict(self) -> dict[str, Any]:
        d: dict[str, Any] = {"label": self.label, "kind": self.kind, "values": self.values}
        if self.meta:
            d["meta"] = self.meta
        if self.children:
            d["children"] = [c.as_dict() for c in self.children]
        return d


@dataclass
class Statement:
    name: str
    title: str
    subtitle: str
    columns: list[str]
    lines: list[Line]
    tree: list[Node] = field(default_factory=list)

    def rows(self) -> list[dict[str, Any]]:
        return [ln.as_row(self.columns) for ln in self.lines]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _months(summary: dict[str, Any]) -> list[str]:
    return list(summary.get("months") or [])


def _zero(columns: Iterable[str]) -> dict[str, float]:
    return {c: 0.0 for c in columns}


def _r(v: float) -> float:
    return round(v, 2) + 0.0  # + 0.0 turns -0.0 into 0.0


def _add(a: dict[str, float], b: dict[str, float], sign: float = 1.0) -> dict[str, float]:
    return {k: _r(a.get(k, 0.0) + sign * b.get(k, 0.0)) for k in set(a) | set(b)}


def _scale(a: dict[str, float], sign: float) -> dict[str, float]:
    return {k: _r(sign * v) for k, v in a.items()}


def _pct(num: dict[str, float], den: dict[str, float]) -> dict[str, float]:
    return {k: (round(num.get(k, 0.0) / den[k], 4) if den.get(k) else 0.0) for k in den}


def _is_zero(values: dict[str, float]) -> bool:
    return all(abs(v) < 0.005 for v in values.values())


# (category, sub) → [(account name, account code, {column: debit-positive amount})]
Accounts = dict[tuple[str, str], list[tuple[str, str, dict[str, float]]]]


def _group(
    rows: list[dict[str, Any]], columns: list[str], value_of, accounts: Accounts | None = None,
) -> dict[str, dict[str, dict[str, float]]]:
    """category → sub_category → {column: debit-positive amount}; fills `accounts` when given."""
    out: dict[str, dict[str, dict[str, float]]] = {}
    for r in rows:
        cat = r.get("category") or ""
        sub = r.get("sub_category") or r.get("account_name") or ""
        bucket = out.setdefault(cat, {}).setdefault(sub, _zero(columns))
        for c in columns:
            bucket[c] = round(bucket[c] + value_of(r, c), 2)
        if accounts is not None:
            accounts.setdefault((cat, sub), []).append(
                (r.get("account_name") or "", r.get("account_code") or "",
                 {c: round(value_of(r, c), 2) for c in columns}))
    return out


def _account_nodes(accts: list[tuple[str, str, dict[str, float]]], sub: str, sign: float) -> list[Node]:
    """Accounts under a sub-category; none when the sub is just one account of the same name."""
    nodes = [Node(name, "account", _scale(vals, sign), meta=code)
             for name, code, vals in sorted(accts, key=lambda a: a[0].lower())]
    nodes = [n for n in nodes if not _is_zero(n.values)]
    if len(nodes) == 1 and nodes[0].label == sub:
        return []
    return nodes


def _section(
    lines: list[Line],
    grouped: dict[str, dict[str, dict[str, float]]],
    categories: list[str],
    columns: list[str],
    sign: float,
    *,
    with_subs: bool,
    node: Node | None = None,
    accounts: Accounts | None = None,
) -> dict[str, float]:
    """Append category (+ sub) lines; return the section total (display sign).

    With `node`, also hang category → sub → account nodes under it.
    """
    total = _zero(columns)
    for cat in categories:
        subs = grouped.get(cat) or {}
        cat_total = _zero(columns)
        for vals in subs.values():
            cat_total = _add(cat_total, vals, sign)
        if not subs:
            continue
        lines.append(Line(cat, "category", cat_total))
        cat_node = Node(cat, "category", cat_total)
        if with_subs:
            for sub in sorted(subs, key=str.lower):
                vals = _scale(subs[sub], sign)
                if not _is_zero(vals):
                    lines.append(Line(sub, "sub", vals))
                    cat_node.children.append(
                        Node(sub, "sub", vals, _account_nodes((accounts or {}).get((cat, sub), []), sub, sign)))
        if node is not None:
            node.children.append(cat_node)
        total = _add(total, cat_total)
    return total


# ---------------------------------------------------------------------------
# P&L
# ---------------------------------------------------------------------------


@dataclass
class PLFigures:
    revenue: dict[str, float]
    cogs: dict[str, float]
    gross_margin: dict[str, float]
    direct_expenses: dict[str, float]
    contribution: dict[str, float]
    other_income: dict[str, float]
    fixed_expenses: dict[str, float]
    ebitda: dict[str, float]
    finance_cost: dict[str, float]
    depreciation: dict[str, float]
    fx: dict[str, float]
    profit_before_tax: dict[str, float]
    income_tax: dict[str, float]
    net_profit: dict[str, float]
    sections: dict[str, Node] = field(default_factory=dict)  # P&L block title → its tree node


def _pl_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    known = set(
        REVENUE_CATS + COGS_CATS + DIRECT_EXP_CATS + OTHER_INCOME_CATS + FIXED_EXP_CATS
        + FINANCE_CATS + DEPRECIATION_CATS + FX_CATS + TAX_CATS
    )
    out = []
    for r in rows:
        if r.get("pl_bs") != cm.PL:
            continue
        if (r.get("category") or "") not in known:
            r = {**r, "category": UNMAPPED_PL, "sub_category": r.get("account_name", "")}
        out.append(r)
    return out


def build_profit_and_loss(rows: list[dict[str, Any]], summary: dict[str, Any]) -> tuple[Statement, PLFigures]:
    months = _months(summary)
    columns = months + [TOTAL]
    pl_rows = _pl_rows(rows)

    def value_of(r: dict[str, Any], c: str) -> float:
        return float(r.get("movement" if c == TOTAL else c) or 0.0)

    accounts: Accounts = {}
    g = _group(pl_rows, columns, value_of, accounts)
    lines: list[Line] = []
    tree: list[Node] = []
    sections: dict[str, Node] = {}

    def block(title: str, cats: list[str], sign: float) -> dict[str, float]:
        lines.append(Line(title, "title"))
        node = Node(title, "section")
        node.values = _section(lines, g, cats, columns, sign, with_subs=True, node=node, accounts=accounts)
        if len(cats) == 1 and node.children:  # one-category block: its subs sit straight under the section
            node.children = node.children[0].children
        tree.append(node)
        sections[title] = node
        return node.values

    def result(label: str, kind: str, values: dict[str, float], *, in_tree: bool = True) -> None:
        lines.append(Line(label, kind, values))
        if in_tree:
            tree.append(Node(label, kind, values))

    revenue = block("Revenue", REVENUE_CATS, -1)
    result("Total Revenue", "total", revenue, in_tree=False)  # the tree's section row carries it
    cogs = block("Cost of Goods Sold", COGS_CATS, +1)
    gm = _add(revenue, cogs, -1)
    result("Gross Margin (GM)", "total", gm)
    result("GM %", "pct", _pct(gm, revenue))
    direct = block("Direct Expenses", DIRECT_EXP_CATS, +1)
    cm_ = _add(gm, direct, -1)
    result("Contribution Margin (CM)", "total", cm_)
    result("CM %", "pct", _pct(cm_, revenue))
    other_income = block("Other Income", OTHER_INCOME_CATS, -1)
    fixed = block("Fixed Expenses", FIXED_EXP_CATS + [UNMAPPED_PL], +1)
    result("Total Fixed Expenses", "total", fixed, in_tree=False)
    ebitda = _add(_add(cm_, other_income), fixed, -1)
    result("EBITDA", "total", ebitda)
    result("EBITDA %", "pct", _pct(ebitda, revenue))
    finance = block("Finance Cost", FINANCE_CATS, +1)
    dep = block("Depreciation", DEPRECIATION_CATS, +1)
    fx = block("Foreign Exchange", FX_CATS, -1)
    pbt = _add(_add(_add(ebitda, finance, -1), dep, -1), fx)
    result("Profit Before Tax", "total", pbt)
    tax = block("Tax", TAX_CATS, +1)
    net = _add(pbt, tax, -1)
    result("Net Profit", "total", net)
    result("Net Profit %", "pct", _pct(net, revenue))

    figures = PLFigures(revenue, cogs, gm, direct, cm_, other_income, fixed, ebitda,
                        finance, dep, fx, pbt, tax, net, sections)
    stmt = Statement(
        name="PL",
        title="Profit and Loss",
        subtitle=_period_label(summary),
        columns=columns,
        lines=lines,
        tree=tree,
    )
    return stmt, figures


# ---------------------------------------------------------------------------
# Executive summary
# ---------------------------------------------------------------------------

# Executive Summary line → the P&L block whose breakdown it expands into.
EXEC_DRILLDOWN = {
    "Revenue Booked": "Revenue",
    "COGS": "Cost of Goods Sold",
    "Direct Expenses": "Direct Expenses",
    "Other Income": "Other Income",
    "Fixed Expenses": "Fixed Expenses",
    "Finance Cost": "Finance Cost",
    "Depreciation": "Depreciation",
    "FX Gain/loss": "Foreign Exchange",
    "Corporate Tax": "Tax",
}


def build_executive_summary(figures: PLFigures, summary: dict[str, Any]) -> Statement:
    f = figures
    rev = f.revenue
    lines = [
        Line("Revenue Booked", "total", rev),
        Line("COGS", "category", f.cogs),
        Line("GM", "total", f.gross_margin),
        Line("GM%", "pct", _pct(f.gross_margin, rev)),
        Line("Direct Expenses", "category", f.direct_expenses),
        Line("CM", "total", f.contribution),
        Line("CM%", "pct", _pct(f.contribution, rev)),
        Line("Other Income", "category", f.other_income),
        Line("Fixed Expenses", "category", f.fixed_expenses),
        Line("EBITDA", "total", f.ebitda),
        Line("EBITDA%", "pct", _pct(f.ebitda, rev)),
        Line("Finance Cost", "category", f.finance_cost),
        Line("Depreciation", "category", f.depreciation),
        Line("FX Gain/loss", "category", f.fx),
        Line("Corporate Tax", "category", f.income_tax),
        Line("Net Profit", "total", f.net_profit),
        Line("Net Profit %", "pct", _pct(f.net_profit, rev)),
    ]
    tree = []
    for ln in lines:
        section = f.sections.get(EXEC_DRILLDOWN.get(ln.label, ""))
        tree.append(Node(ln.label, ln.kind, ln.values, list(section.children) if section else []))
    return Statement(
        name="Executive Summary",
        title="Executive Summary",
        subtitle=f"{_period_label(summary)} · {summary.get('currency_code', '')}",
        columns=_months(summary) + [TOTAL],
        lines=lines,
        tree=tree,
    )


# ---------------------------------------------------------------------------
# Balance sheet
# ---------------------------------------------------------------------------


def _month_end_balances(row: dict[str, Any], months: list[str]) -> dict[str, float]:
    bal = float(row.get("opening") or 0.0)
    out = {}
    for m in months:
        bal += float(row.get(m) or 0.0)
        out[m] = round(bal, 2)
    return out


def build_balance_sheet(rows: list[dict[str, Any]], summary: dict[str, Any]) -> Statement:
    months = _months(summary)
    balances = {id(r): _month_end_balances(r, months) for r in rows}
    known = set(ASSET_CATS + LIABILITY_CATS + EQUITY_CATS)

    bs_rows = []
    pl_cumulative = _zero(months)
    for r in rows:
        if r.get("pl_bs") == cm.PL:
            pl_cumulative = _add(pl_cumulative, balances[id(r)])
            continue
        cat = r.get("category") or ""
        if cat not in known:
            cat = UNMAPPED_ASSETS if r.get("account_type") in ASSET_TYPES else UNMAPPED_LIABILITIES
            r = {**r, "category": cat, "sub_category": r.get("account_name", "")}
        bs_rows.append((r, balances[id(r)]))

    g: dict[str, dict[str, dict[str, float]]] = {}
    for r, bal in bs_rows:
        sub = r.get("sub_category") or r.get("account_name") or ""
        bucket = g.setdefault(r["category"], {}).setdefault(sub, _zero(months))
        for m in months:
            bucket[m] = round(bucket[m] + bal[m], 2)

    lines: list[Line] = [Line("Assets", "title")]
    assets = _section(lines, g, ASSET_CATS + [UNMAPPED_ASSETS], months, +1, with_subs=True)
    lines.append(Line("Total Assets", "total", assets))

    lines.append(Line("Liabilities", "title"))
    liabilities = _section(lines, g, LIABILITY_CATS + [UNMAPPED_LIABILITIES], months, -1, with_subs=True)
    lines.append(Line("Total Liabilities", "total", liabilities))

    lines.append(Line("Represented by (Equity)", "title"))
    equity = _section(lines, g, EQUITY_CATS, months, -1, with_subs=True)
    current_year = _scale(pl_cumulative, -1)
    lines.append(Line(CURRENT_YEAR_EARNINGS, "category", current_year))
    equity = _add(equity, current_year)
    lines.append(Line("Net worth", "total", equity))

    cap_liab = _add(liabilities, equity)
    lines.append(Line("Total Capital & Liabilities", "total", cap_liab))
    return Statement(
        name="BS",
        title="Balance Sheet",
        subtitle=f"As at month end · {summary.get('currency_code', '')}",
        columns=months,
        lines=lines,
    )


def build_financials(rows: list[dict[str, Any]], summary: dict[str, Any]) -> list[Statement]:
    """→ [Executive Summary, PL, BS]."""
    pl, figures = build_profit_and_loss(rows, summary)
    return [build_executive_summary(figures, summary), pl, build_balance_sheet(rows, summary)]


def checks(statements: list[Statement]) -> dict[str, float]:
    """Largest absolute value on each statement's check line (0 when it ties out)."""
    out = {}
    for s in statements:
        for ln in s.lines:
            if ln.kind == "check":
                out[s.name] = round(max((abs(v) for v in ln.values.values()), default=0.0), 2)
    return out
