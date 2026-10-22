"""Same-rows checks for task-2 extractions. No network, no database."""

from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from datetime import date
from decimal import Decimal
from pathlib import Path

FIX = Path(__file__).resolve().parent / "fixtures" / "zoho_sync"


def _ser(obj):
    if isinstance(obj, Decimal):
        return str(obj)
    if isinstance(obj, date):
        return obj.isoformat()
    if isinstance(obj, dict):
        return {k: _ser(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_ser(v) for v in obj]
    return obj


def _load_golden(name: str):
    return json.loads((FIX / name).read_text(encoding="utf-8"))


def _invoice_units_rates(inv: dict):
    units, rates = {}, {}
    for ln in inv["line_items"]:
        ucid = ln.get("unit_conversion_id")
        if ucid:
            units[str(ucid)] = (ln.get("base_unit") or "", Decimal(str(ln.get("conversion_rate") or 1)))
        rates[ln["item_id"]] = Decimal(str(ln.get("purchase_price") or 0))
    return units, rates


class FakeCur:
    def __init__(self, invoices, lines):
        self._invoices = invoices
        self._lines = lines
        self._q = ""

    def execute(self, sql, args=None):
        self._q = sql

    def fetchall(self):
        if "FROM invoice_line_items" in self._q:
            return self._lines
        return self._invoices

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class FakeConn:
    def __init__(self, invoices, lines):
        self._invoices = invoices
        self._lines = lines

    def cursor(self):
        return FakeCur(self._invoices, self._lines)


class FakeGateway:
    """Minimal gateway for account_postings.fetch_pages tests (full FakeGateway is task 3)."""

    def __init__(self, pages_by_key: dict):
        self.pages_by_key = pages_by_key
        self.calls: list[tuple[str, dict]] = []

    def get(self, endpoint: str, params: dict | None = None) -> dict:
        params = dict(params or {})
        self.calls.append((endpoint, params))
        page = int(params.get("page") or 1)
        key = (endpoint, page)
        if key not in self.pages_by_key:
            raise AssertionError(f"unexpected call {endpoint} page={page} params={params}")
        return self.pages_by_key[key]


class SeedMissingSalesRowsTest(unittest.TestCase):
    def test_build_invoice_rows_matches_golden_with_and_without_gl(self) -> None:
        from scripts import seed_missing_sales as sms

        iid = "3331482000188896018"
        inv = json.loads((FIX / f"invoice_{iid}.json").read_text(encoding="utf-8"))["invoice"]
        units, rates = _invoice_units_rates(inv)
        item_ids = {ln["item_id"] for ln in inv["line_items"]}
        cust_ids = {inv["customer_id"]}

        td = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, td, ignore_errors=True)
        (td / f"{iid}.json").write_text((FIX / f"invoice_{iid}.json").read_text(encoding="utf-8"))
        sms.CACHE_DIR = td

        inv_rows, line_rows, ili_rows, stats = sms.build_invoice_rows(
            [iid], units, rates, {iid: Decimal("213.77")}, cust_ids, item_ids
        )
        got = {
            "inv_rows": _ser(inv_rows),
            "line_rows": _ser(line_rows),
            "ili_rows": _ser(ili_rows),
            "stats": dict(stats),
        }
        self.assertEqual(got, _load_golden("golden_seed_missing_sales.json"))

        inv_rows, line_rows, ili_rows, stats = sms.build_invoice_rows(
            [iid], units, rates, {}, cust_ids, item_ids
        )
        got = {
            "inv_rows": _ser(inv_rows),
            "line_rows": _ser(line_rows),
            "ili_rows": _ser(ili_rows),
            "stats": dict(stats),
        }
        self.assertEqual(got, _load_golden("golden_seed_missing_sales_nogl.json"))


class SeedSalesFromInvRowsTest(unittest.TestCase):
    def test_build_rows_matches_golden(self) -> None:
        from scripts import seed_sales_from_inv as ssi

        raw = _load_golden("ssi_input.json")

        def revive(rows):
            out = []
            for r in rows:
                row = dict(r)
                for k, v in list(row.items()):
                    if k in ("date", "due_date") and isinstance(v, str):
                        row[k] = date.fromisoformat(v)
                    elif isinstance(v, str) and k not in (
                        "invoice_id", "invoice_number", "status", "customer_id",
                        "customer_name", "salesperson_name", "currency_code",
                        "line_item_id", "item_id", "item_name", "uom", "base_uom",
                    ):
                        try:
                            row[k] = Decimal(v)
                        except Exception:
                            pass
                out.append(row)
            return out

        invoices = revive(raw["invoices"])
        lines = revive(raw["lines"])
        inv_rows, line_rows, stats = ssi.build_rows(FakeConn(invoices, lines), {"i1", "i2"})
        got = {
            "inv_rows": _ser(inv_rows),
            "line_rows": _ser(line_rows),
            "stats": dict(stats),
        }
        self.assertEqual(got, _load_golden("golden_seed_sales_from_inv.json"))


class SeedPurchasesRowsTest(unittest.TestCase):
    def test_build_matches_golden(self) -> None:
        from scripts import seed_purchases_from_cache as spc

        bill = json.loads((FIX / "bill_3331482000187180271.json").read_text(encoding="utf-8"))
        bdir = Path(tempfile.mkdtemp())
        podir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, bdir, ignore_errors=True)
        self.addCleanup(shutil.rmtree, podir, ignore_errors=True)
        (bdir / "3331482000187180271.json").write_text(
            (FIX / "bill_3331482000187180271.json").read_text(encoding="utf-8"),
            encoding="utf-8",
        )
        spc.KINDS = (
            ("bill", bdir, "bill", "bill_id", "bill_number"),
            ("purchase_order", podir, "purchaseorder", "purchaseorder_id", "purchaseorder_number"),
        )
        units, rates = {}, {}
        for ln in bill["line_items"]:
            ucid = ln.get("unit_conversion_id")
            if ucid:
                units[str(ucid)] = (ln.get("base_unit") or "", Decimal(str(ln.get("conversion_rate") or 1)))
            if ln.get("item_id"):
                rates[ln["item_id"]] = Decimal("1")
        docs, lines, stats = spc.build(date(2026, 9, 1), date(2026, 9, 30), units, rates)
        got = {"docs": _ser(docs), "lines": _ser(lines), "stats": dict(stats)}
        self.assertEqual(got, _load_golden("golden_seed_purchases.json"))


class AccountPostingsTest(unittest.TestCase):
    def test_to_row_matches_golden(self) -> None:
        from common.account_postings import to_row

        page1 = json.loads((FIX / "cos_page1.json").read_text(encoding="utf-8"))
        row = to_row(page1["transactions"][0], page1["page_context"])
        self.assertEqual(_ser(row), _load_golden("golden_to_row.json"))

    def test_fetch_pages_uses_date_start_end_and_reads_every_page(self) -> None:
        from common.account_postings import fetch_pages

        page1 = json.loads((FIX / "cos_page1.json").read_text(encoding="utf-8"))
        page2 = json.loads((FIX / "cos_page2.json").read_text(encoding="utf-8"))
        gw = FakeGateway({
            ("/chartofaccounts/transactions", 1): page1,
            ("/chartofaccounts/transactions", 2): page2,
        })
        pages = fetch_pages(
            "3331482000000034003",
            from_date="2026-09-01",
            to_date="2026-09-30",
            transaction_type=None,
            max_pages=50,
            gateway=gw,
        )
        self.assertEqual(len(pages), 2)
        self.assertEqual(len(pages[0][0]), 1)
        self.assertEqual(len(pages[1][0]), 1)
        self.assertEqual(len(gw.calls), 2)
        for _endpoint, params in gw.calls:
            self.assertIn("date_start", params)
            self.assertIn("date_end", params)
            self.assertNotIn("date.start", params)
            self.assertNotIn("date.end", params)
            self.assertEqual(params["date_start"], "2026-09-01")
            self.assertEqual(params["date_end"], "2026-09-30")
            self.assertEqual(params["account_id"], "3331482000000034003")


class UpsertSqlTest(unittest.TestCase):
    def test_seed_common_upsert_sql_single_and_composite(self) -> None:
        from common.seed_common import upsert_sql

        single = upsert_sql("sales_invoices", ["invoice_id", "total", "cogs"], "invoice_id")
        self.assertIn("ON DUPLICATE KEY UPDATE", single)
        self.assertIn("`total` = VALUES(`total`)", single)
        self.assertNotIn("`invoice_id` = VALUES(`invoice_id`)", single)

        composite = upsert_sql(
            "purchase_docs",
            ["kind", "doc_id", "total"],
            ["kind", "doc_id"],
        )
        self.assertIn("`total` = VALUES(`total`)", composite)
        self.assertNotIn("`kind` = VALUES(`kind`)", composite)
        self.assertNotIn("`doc_id` = VALUES(`doc_id`)", composite)


if __name__ == "__main__":
    unittest.main()
