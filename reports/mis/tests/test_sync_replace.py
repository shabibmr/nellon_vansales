"""Range-replace writes, coverage and date-range pivots against a throwaway MariaDB database.

Skipped unless MIS_TEST_DB_NAME names a database ending in `_test` (created if missing; its dated
tables and runs are wiped), e.g.  MIS_TEST_DB_NAME=nellon_mis_test python -m unittest tests.test_sync_replace
"""

from __future__ import annotations

import os
import unittest
from datetime import date
from unittest import mock

from reports import db, periods

TEST_DB = os.getenv("MIS_TEST_DB_NAME", "")
D = date


def line(iid: str, day: str, item: str = "Milk", net: float = 10.0, cost: float = 6.0, flag: str = "") -> dict:
    return {"invoice_id": iid, "invoice_number": f"INV-{iid}", "month": day[:7], "date": day,
            "customer_name": "Cust", "salesperson_name": "Rep", "van": "Van 1", "item_id": item,
            "item_name": item, "sku": "", "unit": "pcs", "quantity": 1, "conversion_rate": 1,
            "base_quantity": 1, "rate": net, "gross_amount": net, "line_discount": 0, "invoice_discount": 0,
            "net_sales": net, "cost_rate": cost, "cost": cost, "gross_margin": net - cost, "flag": flag,
            "cost_source": "booked"}


def pline(kind: str, doc: str, day: str, vendor: str = "V1", amount: float = 100.0) -> dict:
    return {"kind": kind, "doc_id": doc, "month": day[:7], "date": day, "number": doc, "vendor_name": vendor,
            "status": "open", "item_id": "i", "item_name": "Milk", "sku": "", "unit": "pcs",
            "quantity": 1, "rate": amount, "amount": amount}


@unittest.skipUnless(TEST_DB.endswith("_test"), "set MIS_TEST_DB_NAME=<name>_test to run DB tests")
class SyncReplaceTests(unittest.TestCase):
    def setUp(self) -> None:
        patcher = mock.patch.dict(os.environ, {"MIS_DB_NAME": TEST_DB})
        patcher.start()
        self.addCleanup(patcher.stop)
        db.init_schema()
        with db.connect() as conn, conn.cursor() as cur:
            for t in ("sales_lines", "sales_invoices", "purchase_doc_lines", "sync_coverage", "report_runs"):
                cur.execute(f"DELETE FROM {t}")

    def q(self, sql: str, *params) -> list[dict]:
        with db.connect() as conn, conn.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchall()

    def test_voided_invoice_disappears(self) -> None:
        db.sync_sales("2026-09-01", "2026-09-30", None, [line("A", "2026-09-02"), line("B", "2026-09-03")], source="zoho")
        db.sync_sales("2026-09-01", "2026-09-30", None, [line("A", "2026-09-02")], source="zoho")
        self.assertEqual([r["invoice_id"] for r in self.q("SELECT invoice_id FROM sales_invoices")], ["A"])
        self.assertEqual(len(self.q("SELECT 1 FROM sales_lines")), 1)

    def test_invoice_date_moved_into_range(self) -> None:
        db.sync_sales("2026-09-01", "2026-09-30", None, [line("C", "2026-09-10"), line("D", "2026-09-11")], source="zoho")
        db.sync_sales("2026-10-01", "2026-10-05", None, [line("C", "2026-10-02")], source="zoho")
        rows = self.q("SELECT invoice_id, date FROM sales_invoices ORDER BY invoice_id")
        self.assertEqual([(r["invoice_id"], r["date"]) for r in rows], [("C", D(2026, 10, 2)), ("D", D(2026, 9, 11))])
        self.assertEqual(db.get_coverage("sales")["merged"], [{"from": "2026-09-01", "to": "2026-10-05"}])

    def test_line_numbers_restart_per_invoice(self) -> None:
        db.sync_sales("2026-09-01", "2026-09-30", None,
                      [line("A", "2026-09-02"), line("B", "2026-09-02"), line("A", "2026-09-02", "Bread")], source="zoho")
        rows = self.q("SELECT invoice_id, line_no, item_name FROM sales_lines ORDER BY invoice_id, line_no")
        self.assertEqual([(r["invoice_id"], r["line_no"], r["item_name"]) for r in rows],
                         [("A", 1, "Milk"), ("A", 2, "Bread"), ("B", 1, "Milk")])
        head = self.q("SELECT line_count, net_sales FROM sales_invoices WHERE invoice_id='A'")[0]
        self.assertEqual((head["line_count"], float(head["net_sales"])), (2, 20.0))

    def test_coverage_trims_older_rows(self) -> None:
        db.sync_sales("2026-09-01", "2026-09-30", None, [], source="zoho")
        db.sync_sales("2026-09-10", "2026-09-15", None, [], source="cache")
        cov = db.get_coverage("sales")
        self.assertEqual([(r["from"], r["to"], r["source"]) for r in cov["ranges"]],
                         [("2026-09-01", "2026-09-09", "zoho"), ("2026-09-10", "2026-09-15", "cache"),
                          ("2026-09-16", "2026-09-30", "zoho")])
        self.assertEqual(cov["gaps"], [])

    def test_kind_scoping(self) -> None:
        db.sync_purchases("2026-09-01", "2026-09-30",
                          [pline("bill", "b1", "2026-09-05"), pline("purchase_order", "p1", "2026-09-06")], source="zoho")
        db.sync_purchases("2026-09-01", "2026-09-30", [], source="zoho", kinds=["bill"])
        self.assertEqual([r["kind"] for r in self.q("SELECT kind FROM purchase_doc_lines")], ["purchase_order"])
        self.assertTrue(db.get_coverage("purchases:bill")["ranges"])
        with self.assertRaises(ValueError):
            db.sync_purchases("2026-09-01", "2026-09-30", [], source="zoho", kinds=["invoice"])

    def test_margin_pivot_columns_and_gm_pct(self) -> None:
        db.sync_sales("2026-09-01", "2026-10-31", None, [
            line("A", "2026-09-05", "Milk", 100, 50), line("B", "2026-10-05", "Milk", 300, 270),
            line("C", "2026-10-06", "Bread", 100, 100, flag="no cost"),
        ], source="zoho")
        cols = periods.month_cols(D(2026, 9, 1), D(2026, 10, 31))
        p = db.get_margin_pivot_range(cols, "item", "gm_pct")
        self.assertEqual(p["columns"], ["2026-09", "2026-10", "Total"])
        milk = next(r for r in p["rows"] if r["label"] == "Milk")
        self.assertEqual(milk["values"], {"2026-09": 0.5, "2026-10": 0.1, "Total": 0.2})  # 80/400, not avg(50%, 10%)
        bread = next(r for r in p["rows"] if r["label"] == "Bread")
        self.assertNotIn("2026-09", bread["values"])  # no data → no cell
        self.assertEqual(bread["flagged"], 1)
        self.assertEqual(p["total"]["Total"], round(80 / 500, 4))
        self.assertEqual([r["label"] for r in p["rows"]], ["Milk", "Bread"])  # by net sales
        part = db.get_margin_pivot_range(periods.parse_cols("x:2026-10-06:2026-10-06"), "item", "net_sales")
        self.assertEqual(part["total"], {"x": 100.0})

    def test_purchase_documents_are_distinct(self) -> None:
        db.sync_purchases("2026-09-01", "2026-09-30", [
            pline("bill", "b1", "2026-09-05", "V1"), pline("bill", "b1", "2026-09-05", "V1"),
            pline("bill", "b2", "2026-09-20", "V2"), pline("purchase_order", "b1", "2026-09-21", "V2"),
        ], source="zoho")
        p = db.get_purchase_pivot_range(periods.parse_cols("a:2026-09-01:2026-09-15,b:2026-09-16:2026-09-30"),
                                        "vendor", "documents")
        self.assertEqual(p["total"], {"a": 1.0, "b": 2.0})
        self.assertEqual({r["label"]: r["values"] for r in p["rows"]}, {"V1": {"a": 1.0}, "V2": {"b": 2.0}})

    def test_migration_newest_run_wins(self) -> None:
        summary = {"from_date": "2026-09-01", "to_date": "2026-09-30"}
        db.save_margin_run([line("A", "2026-09-02", net=10), line("B", "2026-09-03")], summary, source="old")
        db.save_margin_run([line("A", "2026-09-02", net=99)], summary, source="new")
        db.migrate_runs_to_dated()
        first = self.q("SELECT invoice_id, net_sales FROM sales_lines")
        self.assertEqual([(r["invoice_id"], float(r["net_sales"])) for r in first], [("A", 99.0)])
        db.migrate_runs_to_dated()
        self.assertEqual(self.q("SELECT invoice_id, net_sales FROM sales_lines"), first)
        self.assertEqual(db.get_coverage("sales")["ranges"][0]["source"], "migrated")


if __name__ == "__main__":
    unittest.main()
