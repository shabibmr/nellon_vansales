"""Report SQL fragments and the accounts → snapshot mapping — no DB, no network.

    .venv/bin/python -m unittest tests.test_report_sql
"""

from __future__ import annotations

import unittest

from reports import db


class SqlFragmentTests(unittest.TestCase):
    def test_status_filters(self) -> None:
        self.assertIn("'draft'", db._MARGIN_WHERE)
        self.assertIn("'void'", db._MARGIN_WHERE)
        self.assertIn("'cancelled'", db._PURCHASE_WHERE)

    def test_margin_dimensions(self) -> None:
        self.assertEqual(db.MARGIN_DIMENSIONS["item"], "l.item_name")
        self.assertEqual(db.MARGIN_DIMENSIONS["location"], "l.location_name")
        self.assertIn("(warehouse)", db.MARGIN_DIMENSIONS["van"])

    def test_cogs_comes_from_line_cogs(self) -> None:
        self.assertEqual(db._MARGIN_SUMS["cost"], "l.cogs")
        self.assertEqual(db._MARGIN_SUMS["gross_margin"], "l.net_sales - l.cogs")

    def test_unknown_dimension_rejected(self) -> None:
        with self.assertRaises(ValueError):
            db.get_margin_pivot_range([], "nope", "net_sales")
        with self.assertRaises(ValueError):
            db.get_purchase_pivot_range([], "vendor", "nope")
        with self.assertRaises(ValueError):
            db.get_margin_detail_range(None, None, "nope")  # type: ignore[arg-type]


ACCOUNTS = [
    {"account_id": 1, "account_code": "100", "account_name": "Assets", "account_type": "other_asset",
     "pl_bs": "BS", "category": "Assets"},
    {"account_id": 2, "account_code": "110", "account_name": "Bank", "account_type": "bank",
     "parent_account_id": 1, "parent_account_name": "Assets", "pl_bs": "BS", "category": "Cash", "source": "rule"},
    {"account_id": 3, "account_name": "Sales", "account_type": "income", "pl_bs": "PL", "category": "Revenue",
     "is_active": 0},
]


class AccountsMappingTests(unittest.TestCase):
    def test_category_rows(self) -> None:
        rows = db.category_rows_from_accounts(ACCOUNTS, "Acme")
        self.assertEqual([r["account_id"] for r in rows], ["1", "2", "3"])  # BS first, then by path
        bank = rows[1]
        self.assertEqual(bank["concate"], "BankAcme")
        self.assertEqual(bank["path"], "Assets > Bank")
        self.assertFalse(rows[2]["is_active"])

    def test_snapshot_shape(self) -> None:
        snap = db.snapshot_from_db(ACCOUNTS, {"name": "Acme", "currency_code": "AED", "fiscal_year_start_month": 4})
        self.assertEqual(snap["organization_name"], "Acme")
        self.assertEqual(snap["fiscal_year_start_month"], 4)
        self.assertEqual(len(snap["accounts"]), 3)
        self.assertEqual(len(snap["categories"]), 3)
        self.assertEqual(snap["accounts"][1]["parent_account_id"], 1)


if __name__ == "__main__":
    unittest.main()
