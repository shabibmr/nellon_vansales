"""Expandable P&L / Executive Summary trees: every parent is the sum of its children."""

from __future__ import annotations

import unittest

from reports.financials import Node, TOTAL, build_balance_sheet, build_executive_summary, build_profit_and_loss

MONTHS = ["2026-04", "2026-05"]
SUMMARY = {"months": MONTHS, "from_date": "2026-04-01", "to_date": "2026-05-31", "currency_code": "AED"}


def acct(code: str, name: str, cat: str, sub: str, apr: float, may: float) -> dict:
    return {"account_id": code, "account_code": code, "account_name": name, "pl_bs": "PL",
            "category": cat, "sub_category": sub, "2026-04": apr, "2026-05": may, "movement": apr + may}


# TB amounts are debit-positive: income negative, costs positive.
ROWS = [
    acct("4001", "Sales - Van 1", "Revenue Booked", "Van Sales", -600, -700),
    acct("4002", "Sales - Van 2", "Revenue Booked", "Van Sales", -400, -300),
    acct("4100", "Rebate Income", "Direct Income", "Rebates", -50, 0),
    acct("5001", "Cost of Goods Sold", "COGS", "Cost of Goods Sold", 600, 650),
    acct("6001", "Fuel Van 1", "Direct Expenses", "Fuel", 30, 35),
    acct("6002", "Fuel Van 2", "Direct Expenses", "Fuel", 20, 25),
    acct("7001", "Salaries", "Employee Costs", "Salaries", 100, 100),
    acct("7002", "Visa Costs", "Employee Costs", "Visa", 10, 0),
    acct("7100", "Rent", "Office Expenses", "Rent", 50, 50),
    acct("7999", "Mystery Account", "Not a category", "", 5, 0),
    acct("8001", "Bank Charges", "Finance Cost", "Bank Charges", 2, 3),
]


def walk(nodes: list[Node]):
    for n in nodes:
        yield n
        yield from walk(n.children)


class TreeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.pl, self.fig = build_profit_and_loss(ROWS, SUMMARY)
        self.ex = build_executive_summary(self.fig, SUMMARY)

    def test_parents_sum_children(self) -> None:
        for tree in (self.pl.tree, self.ex.tree):
            for n in walk(tree):
                if n.children:
                    for c in MONTHS + [TOTAL]:
                        self.assertAlmostEqual(n.values[c], sum(ch.values[c] for ch in n.children), 2,
                                               f"{n.label} / {c}")

    def test_pl_tree_follows_flat_statement(self) -> None:
        flat = {ln.label: ln.values for ln in self.pl.lines if ln.kind in ("total", "pct", "check")}
        for n in self.pl.tree:
            if n.kind != "section":
                self.assertEqual(n.values, flat[n.label])
        rev = next(n for n in self.pl.tree if n.label == "Revenue")
        self.assertEqual(rev.values, flat["Total Revenue"])
        self.assertEqual([c.label for c in rev.children], ["Revenue Booked", "Direct Income"])
        labels = [n.label for n in self.pl.tree]
        self.assertNotIn("Total Revenue", labels)
        self.assertNotIn("Total Fixed Expenses", labels)

    def test_accounts_under_subs(self) -> None:
        rev = next(n for n in self.pl.tree if n.label == "Revenue")
        van = rev.children[0].children[0]
        self.assertEqual(van.label, "Van Sales")
        self.assertEqual([a.label for a in van.children], ["Sales - Van 1", "Sales - Van 2"])
        self.assertEqual(van.children[0].meta, "4001")
        self.assertEqual(van.children[0].values[TOTAL], 1300)  # credit-positive on display
        # A sub that is just one same-named account has no children.
        cogs = next(n for n in self.pl.tree if n.label == "Cost of Goods Sold")
        self.assertEqual([c.label for c in cogs.children], ["Cost of Goods Sold"])
        self.assertEqual(cogs.children[0].children, [])

    def test_single_category_block_is_flattened(self) -> None:
        direct = next(n for n in self.pl.tree if n.label == "Direct Expenses")
        self.assertEqual([c.label for c in direct.children], ["Fuel"])  # no "Direct Expenses" level

    def test_executive_summary_drills_into_pl(self) -> None:
        by = {n.label: n for n in self.ex.tree}
        self.assertEqual([c.label for c in by["Fixed Expenses"].children],
                         ["Employee Costs", "Office Expenses", "Unmapped P&L accounts"])
        self.assertEqual(by["Revenue Booked"].values[TOTAL], 2050)
        self.assertEqual(by["GM"].children, [])
        self.assertEqual(by["Corporate Tax"].children, [])  # no tax accounts
        self.assertEqual([n.label for n in self.ex.tree], [ln.label for ln in self.ex.lines])

    def test_as_dict_omits_empty(self) -> None:
        d = next(n for n in self.ex.tree if n.label == "GM").as_dict()
        self.assertNotIn("children", d)
        self.assertNotIn("meta", d)


if __name__ == "__main__":
    unittest.main()


class UnmappedBalanceSheetRowTest(unittest.TestCase):
    def test_unmapped_account_keeps_its_balance(self):
        rows = [{"account_id": "1", "account_name": "Mystery", "account_type": "other_current_asset",
                 "pl_bs": "BS", "category": "", "balances": {"2026-09": 5.0}}]
        stmt = build_balance_sheet(rows, {"months": ["2026-09"]})
        self.assertTrue(any(ln.label == "Mystery" for ln in stmt.lines))
