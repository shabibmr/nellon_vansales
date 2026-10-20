"""Tests for `zoho_sync` (task list, section 10). No network, no database.

This file starts with the "Core" tests over the pieces that need neither Zoho
nor MariaDB: `store.MemoryStore`, `gateway.FakeGateway`/`ReplayGateway`,
`budget.Budget`, `cache.Cache`, `runlog.RunLog`, and `watermark.py`. Masters,
specs, pipeline, and Cost of Sales tests land in their own sections as those
modules are built (task list, section 10).
"""

from __future__ import annotations

import json
import time
import unittest
from datetime import date, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from tempfile import TemporaryDirectory

from unittest import mock

from zoho_client import ZohoHTTPError
from zoho_sync import cogs, pipeline, postings
from zoho_sync import __main__ as zoho_sync_main
from zoho_sync.budget import Budget, BudgetExceeded
from zoho_sync.cache import Cache
from zoho_sync.context import Run
from zoho_sync.gateway import FakeGateway, LiveGateway, NotFound, PageNotFound, ReplayGateway
from zoho_sync.masters import WrongType, ensure
from zoho_sync.pipeline import PER_PAGE
from zoho_sync.ranges import (
    DateRange,
    cost_of_sales_ranges,
    format_range_doc_id,
    merge_ranges,
    parse_pending_doc_id,
    trailing_window,
)
from zoho_sync.runlog import RunLog, cleanup_old_runs, new_run_id
from zoho_sync.specs import (
    ALL_SPECS,
    BILLS,
    DEBIT_NOTES,
    INVOICES,
    PURCHASE_ORDERS,
    SALES_ORDERS,
    VENDOR_CREDITS,
    VENDOR_PAYMENTS,
)
from zoho_sync.store import MemoryStore, RowNotFound
from zoho_sync.store_db import DbStore, UnknownColumn
from zoho_sync.watermark import (
    NoWatermark,
    get_watermark,
    highest,
    seed,
    set_watermark,
    to_zoho_watermark,
)

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "zoho_sync"


def _load_fixture(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


def _test_run(gateway: FakeGateway, store: MemoryStore | None = None, cache_root: Path | None = None) -> Run:
    root = cache_root or Path("/tmp/zoho_sync_test_cache_unused")
    return Run(
        gateway=gateway,
        store=store or MemoryStore(),
        cache=Cache(root),
        runlog=RunLog(root, "20261021-020000"),
        run_id="20261021-020000",
        mode="test",
    )


WM = "2026-10-01T10:00:00+0400"
WM_LATER = "2026-10-02T12:00:00+0400"


def _list_params(page: int = 1, **extra: object) -> dict:
    params: dict = {"last_modified_time": WM, "page": page, "per_page": PER_PAGE}
    params.update(extra)
    return params


def _seed_sales_masters(store: MemoryStore) -> None:
    store.upsert("customers", [{"customer_id": "C1", "contact_name": "Acme"}])
    store.upsert("items", [{"item_id": "IT1", "name": "Item", "purchase_rate": Decimal("20")}])
    store.upsert("salespersons", [{"salesperson_id": "SP1", "salesperson_name": "Sam"}])
    store.upsert("locations", [{"location_id": "L1", "location_name": "HQ"}])


def _seed_vendor_masters(store: MemoryStore) -> None:
    store.upsert("vendors", [{"vendor_id": "V1", "contact_name": "Vendor"}])
    store.upsert("items", [{"item_id": "IT1", "name": "Item", "purchase_rate": Decimal("20")}])
    store.upsert("locations", [{"location_id": "L1", "location_name": "HQ"}])
    store.upsert("accounts", [{"account_id": "A1", "account_name": "Cash"}])


def _contact(cid: str, contact_type: str, name: str = "Acme") -> dict:
    return {
        "contact_id": cid,
        "contact_name": name,
        "company_name": name,
        "contact_type": contact_type,
        "status": "active",
        "currency_code": "AED",
        "payment_terms": 0,
        "payment_terms_label": "Due on Receipt",
        "credit_limit": "0",
        "last_modified_time": WM,
    }


class _StubZohoClient:
    """Minimal ZohoClient stand-in: signs in on first get via on_auth; no network."""

    def __init__(self, on_auth=None) -> None:
        self._on_auth = on_auth
        self._authed = False
        self.calls: list[tuple[str, dict | None]] = []
        self.queue: list[object] = []

    def get(self, endpoint: str, params: dict | None = None) -> dict:
        if not self._authed:
            if self._on_auth:
                self._on_auth()
            self._authed = True
        self.calls.append((endpoint, params))
        if not self.queue:
            raise AssertionError("stub client: no queued response")
        item = self.queue.pop(0)
        if isinstance(item, Exception):
            raise item
        return item  # type: ignore[return-value]


class StoreTests(unittest.TestCase):
    def test_upsert_then_get(self) -> None:
        store = MemoryStore()
        store.upsert("customers", [{"customer_id": "C1", "name": "Acme", "status": "active"}])
        self.assertEqual(store.get("customers", "C1"), {"customer_id": "C1", "name": "Acme", "status": "active"})
        self.assertTrue(store.has("customers", "C1"))
        self.assertFalse(store.has("customers", "C2"))

    def test_upsert_composite_key(self) -> None:
        store = MemoryStore()
        store.upsert("purchase_docs", [{"kind": "bill", "doc_id": "B1", "number": "BILL-1"}])
        self.assertEqual(store.get("purchase_docs", ("bill", "B1"))["number"], "BILL-1")

    def test_upsert_respects_update_cols(self) -> None:
        store = MemoryStore()
        store.upsert("accounts", [{"account_id": "A1", "category": "COGS", "pl_bs": "pl"}])
        # A later upsert naming only the Zoho columns must not touch category/pl_bs.
        store.upsert("accounts", [{"account_id": "A1", "category": "stale"}], update_cols=["account_id"])
        self.assertEqual(store.get("accounts", "A1")["category"], "COGS")

    def test_update_changes_only_named_columns(self) -> None:
        store = MemoryStore()
        store.upsert("customers", [{"customer_id": "C1", "name": "Acme", "status": "active"}])
        store.update("customers", "C1", {"status": "inactive"})
        self.assertEqual(store.get("customers", "C1"), {"customer_id": "C1", "name": "Acme", "status": "inactive"})

    def test_transaction_commits_once_and_rolls_back_on_error(self) -> None:
        class StubCur:
            rowcount = 1

            def execute(self, sql: str, args: tuple = ()) -> None:
                pass

            def __enter__(self) -> StubCur:
                return self

            def __exit__(self, *exc: object) -> None:
                pass

        class StubConn:
            commits = 0
            rollbacks = 0

            def cursor(self) -> StubCur:
                return StubCur()

            def commit(self) -> None:
                self.commits += 1

            def rollback(self) -> None:
                self.rollbacks += 1

        conn = StubConn()
        store = DbStore(conn=conn, columns={"sales_lines": {"line_item_id", "cogs"}})
        with store.transaction():
            store.update("sales_lines", "L1", {"cogs": Decimal("1")})
            store.update("sales_lines", "L2", {"cogs": Decimal("2")})
        self.assertEqual((conn.commits, conn.rollbacks), (1, 0))
        with self.assertRaises(RuntimeError):
            with store.transaction():
                store.update("sales_lines", "L1", {"cogs": Decimal("3")})
                raise RuntimeError("boom")
        self.assertEqual((conn.commits, conn.rollbacks), (1, 1))

    def test_update_missing_row_raises(self) -> None:
        store = MemoryStore()
        with self.assertRaises(RowNotFound):
            store.update("customers", "C1", {"status": "inactive"})

    def test_replace_lines_deletes_missing(self) -> None:
        store = MemoryStore()
        store.upsert(
            "sales_lines",
            [
                {"line_item_id": "L1", "invoice_id": "I1", "item_total": "10"},
                {"line_item_id": "L2", "invoice_id": "I1", "item_total": "20"},
            ],
        )
        store.replace_lines(
            "sales_lines", "invoice_id", "I1", [{"line_item_id": "L1", "invoice_id": "I1", "item_total": "11"}]
        )
        self.assertTrue(store.has("sales_lines", "L1"))
        self.assertFalse(store.has("sales_lines", "L2"))
        self.assertEqual(store.get("sales_lines", "L1")["item_total"], "11")

    def test_replace_range_deletes_missing_in_range(self) -> None:
        store = MemoryStore()
        store.replace_range(
            "A1",
            date(2026, 10, 1),
            date(2026, 10, 31),
            [
                {"account_id": "A1", "categorized_transaction_id": "T1", "transaction_date": date(2026, 10, 5), "amount": "1"},
                {"account_id": "A1", "categorized_transaction_id": "T2", "transaction_date": date(2026, 10, 6), "amount": "2"},
            ],
        )
        # Zoho replaced T2 under a new id and dropped the old one from the page.
        store.replace_range(
            "A1",
            date(2026, 10, 1),
            date(2026, 10, 31),
            [
                {"account_id": "A1", "categorized_transaction_id": "T1", "transaction_date": date(2026, 10, 5), "amount": "1"},
                {"account_id": "A1", "categorized_transaction_id": "T3", "transaction_date": date(2026, 10, 6), "amount": "2"},
            ],
        )
        ids = {row["categorized_transaction_id"] for row in store.gl_journal_rows()}
        self.assertEqual(ids, {"T1", "T3"})

    def test_max_value_empty_table(self) -> None:
        store = MemoryStore()
        self.assertIsNone(store.max_value("sales_invoices", "last_modified_time"))

    def test_pending_tracks_attempts(self) -> None:
        store = MemoryStore()
        store.add_pending("invoices", "I1", modified_time="t1", reason="master fetch failed", error="boom")
        store.add_pending("invoices", "I1", modified_time="t1", reason="master fetch failed", error="boom again")
        rows = store.list_pending("invoices")
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["attempts"], 2)
        store.clear_pending("invoices", "I1")
        self.assertEqual(store.list_pending("invoices"), [])

    def test_keyed_reads_return_same_rows_as_iter_table(self) -> None:
        store = MemoryStore()
        store.upsert("sales_lines", [
            {"line_item_id": "L1", "invoice_id": "INV1", "cogs": Decimal("10")},
            {"line_item_id": "L2", "invoice_id": "INV2", "cogs": Decimal("20")},
            {"line_item_id": "L3", "invoice_id": "INV1", "cogs": Decimal("30")},
        ])
        all_lines = list(store.iter_table("sales_lines"))
        manual_filter = [ln for ln in all_lines if ln.get("invoice_id") == "INV1"]
        keyed_filter = store.iter_where("sales_lines", where_in={"invoice_id": ["INV1"]})
        self.assertEqual(manual_filter, keyed_filter)


class WatermarkTests(unittest.TestCase):
    def test_round_trip(self) -> None:
        store = MemoryStore()
        set_watermark(store, "invoices", "2026-10-21T14:02:51+0400")
        self.assertEqual(get_watermark(store, "invoices"), "2026-10-21T14:02:51+0400")

    def test_missing_watermark_raises(self) -> None:
        store = MemoryStore()
        with self.assertRaises(NoWatermark):
            get_watermark(store, "invoices")

    def test_requests_encodes_watermark_plus_once(self) -> None:
        import requests
        req = requests.Request(
            "GET",
            "https://books.zoho.com/api/v3/invoices",
            params={"last_modified_time": "2026-10-21T14:02:51+0400"},
        )
        prep = req.prepare()
        self.assertIn("%2B0400", prep.url)
        self.assertNotIn("%252B", prep.url)

    def test_to_zoho_watermark_midnight_and_single_digits(self) -> None:
        dt = datetime(2026, 5, 4, 0, 5, 9)
        self.assertEqual(to_zoho_watermark(dt), "2026-05-04T00:05:09+0400")

    def test_seed_from_datetime_and_has_t_and_offset(self) -> None:
        store = MemoryStore()
        store.upsert("sales_invoices", [{"invoice_id": "I1", "last_modified_time": "2026-10-21 14:02:51"}])
        result = seed(store, {"invoices": "sales_invoices", "bills": "purchase_docs"})
        self.assertEqual(result["invoices"], "2026-10-21T14:02:51+0400")
        self.assertIsNone(result["bills"])
        self.assertEqual(get_watermark(store, "invoices"), "2026-10-21T14:02:51+0400")
        with self.assertRaises(NoWatermark):
            get_watermark(store, "bills")

    def test_seed_shared_table_uses_each_datasets_own_kind(self) -> None:
        store = MemoryStore()
        store.upsert("purchase_docs", [
            {"kind": "bill", "doc_id": "B1", "last_modified_time": "2026-10-21 14:00:00"},
            {"kind": "purchase_order", "doc_id": "P1", "last_modified_time": "2026-10-01 09:00:00"},
        ])
        result = seed(
            store,
            {"bills": "purchase_docs", "purchase_orders": "purchase_docs"},
            kinds={"bills": "bill", "purchase_orders": "purchase_order"},
        )
        self.assertEqual(result["bills"], "2026-10-21T14:00:00+0400")
        self.assertEqual(result["purchase_orders"], "2026-10-01T09:00:00+0400")

    def test_highest_orders_mixed_offsets_correctly(self) -> None:
        t_utc = "2026-10-01T10:00:00+0000"
        t_dubai = "2026-10-01T12:00:00+0400"
        self.assertEqual(highest(t_dubai, t_utc), t_utc)
        self.assertEqual(highest(t_utc, t_dubai), t_utc)


class FakeGatewayTests(unittest.TestCase):
    def test_matches_on_endpoint_and_params(self) -> None:
        gw = FakeGateway()
        gw.add("/invoices", {"last_modified_time_after": "t1", "page": 1}, {"invoices": [{"invoice_id": "I1"}]})
        result = gw.get("/invoices", {"page": 1, "last_modified_time_after": "t1"})
        self.assertEqual(result["invoices"][0]["invoice_id"], "I1")
        self.assertEqual(gw.calls, [("/invoices", {"page": 1, "last_modified_time_after": "t1"})])

    def test_missing_fixture_raises(self) -> None:
        gw = FakeGateway()
        with self.assertRaises(PageNotFound):
            gw.get("/invoices", {"page": 1})


class LiveGatewayTests(unittest.TestCase):
    def test_unused_client_makes_no_call(self) -> None:
        with TemporaryDirectory() as tmp:
            budget = Budget(Path(tmp) / "stamp", interval=0)
            client = _StubZohoClient(on_auth=budget.before_call)
            LiveGateway(client, budget, RunLog(Path(tmp), "20261021-020000"), sleep=lambda _s: None)
            self.assertEqual(client.calls, [])
            self.assertFalse(client._authed)
            self.assertEqual(budget.calls_made, 0)

    def test_first_call_signs_in_and_counts_auth(self) -> None:
        with TemporaryDirectory() as tmp:
            budget = Budget(Path(tmp) / "stamp", interval=0)
            client = _StubZohoClient(on_auth=budget.before_call)
            client.queue.append({"invoices": []})
            gw = LiveGateway(client, budget, RunLog(Path(tmp), "20261021-020000"), sleep=lambda _s: None)
            gw.get("/invoices", {"page": 1})
            # one before_call for the request + one for on_auth sign-in
            self.assertEqual(budget.calls_made, 2)
            self.assertTrue(client._authed)
            self.assertEqual(client.calls, [("/invoices", {"page": 1})])

    def test_retries_429_then_succeeds(self) -> None:
        with TemporaryDirectory() as tmp:
            budget = Budget(Path(tmp) / "stamp", interval=0)
            client = _StubZohoClient(on_auth=budget.before_call)
            client.queue.extend(
                [
                    ZohoHTTPError("rate", status=429),
                    {"invoices": [{"invoice_id": "I1"}]},
                ]
            )
            slept: list[float] = []
            gw = LiveGateway(
                client,
                budget,
                RunLog(Path(tmp), "20261021-020000"),
                sleep=slept.append,
                backoff=(0.5, 1.0),
            )
            body = gw.get("/invoices", {"page": 1})
            self.assertEqual(body["invoices"][0]["invoice_id"], "I1")
            self.assertEqual(slept, [0.5])
            # auth once + two request attempts
            self.assertEqual(budget.calls_made, 3)

    def test_404_raises_not_found(self) -> None:
        with TemporaryDirectory() as tmp:
            budget = Budget(Path(tmp) / "stamp", interval=0)
            client = _StubZohoClient(on_auth=budget.before_call)
            client.queue.append(ZohoHTTPError("gone", status=404))
            gw = LiveGateway(client, budget, RunLog(Path(tmp), "20261021-020000"), sleep=lambda _s: None)
            with self.assertRaises(NotFound):
                gw.get("/contacts/missing")


class IterWhereDateTests(unittest.TestCase):
    def test_date_column_with_no_ranges_returns_no_rows(self) -> None:
        store = MemoryStore()
        store.upsert("sales_invoices", [{"invoice_id": "I1", "date": date(2026, 10, 1)}])
        self.assertEqual(store.iter_where("sales_invoices", date_column="date", date_ranges=[]), [])


class StoreDbTests(unittest.TestCase):
    def test_rejects_mapper_key_that_is_not_a_column(self) -> None:
        store = DbStore(conn=None, columns={"customers": {"customer_id", "contact_name", "status"}})
        with self.assertRaises(UnknownColumn):
            store.upsert("customers", [{"customer_id": "C1", "contact_name": "Acme", "nope": "x"}])

    def test_update_builds_expected_sql(self) -> None:
        class StubCur:
            def __init__(self) -> None:
                self.sql = ""
                self.args: tuple = ()
                self.rowcount = 1

            def execute(self, sql: str, args: tuple = ()) -> None:
                self.sql = sql
                self.args = args

            def __enter__(self) -> StubCur:
                return self

            def __exit__(self, *exc: object) -> None:
                pass

        class StubConn:
            def __init__(self, cur: StubCur) -> None:
                self.cur = cur
                self.committed = False

            def cursor(self) -> StubCur:
                return self.cur

            def commit(self) -> None:
                self.committed = True

        cur = StubCur()
        conn = StubConn(cur)
        store = DbStore(conn=conn, columns={"sales_invoices": {"invoice_id", "status", "cogs", "cogs_synced_at"}})
        now = datetime(2026, 10, 21, 2, 0, 0)
        store.update("sales_invoices", "INV1", {"cogs": Decimal("15.50"), "cogs_synced_at": now})
        self.assertEqual(
            cur.sql,
            "UPDATE `sales_invoices` SET `cogs` = %s, `cogs_synced_at` = %s WHERE `invoice_id` = %s",
        )
        self.assertEqual(cur.args, (Decimal("15.50"), now, "INV1"))
        self.assertTrue(conn.committed)

    def test_update_identical_values_is_not_a_missing_row(self) -> None:
        # pymysql without FOUND_ROWS reports changed rows, so an UPDATE that
        # rewrites the same values returns rowcount 0 for an existing row.
        class StubCur:
            rowcount = 0

            def execute(self, sql: str, args: tuple = ()) -> None:
                self.last_sql = sql

            def fetchone(self) -> dict:
                return {"1": 1} if self.last_sql.startswith("SELECT") else None

            def __enter__(self) -> StubCur:
                return self

            def __exit__(self, *exc: object) -> None:
                pass

        class StubConn:
            def cursor(self) -> StubCur:
                return StubCur()

            def commit(self) -> None:
                pass

        store = DbStore(conn=StubConn(), columns={"sales_invoices": {"invoice_id", "cogs"}})
        store.update("sales_invoices", "INV1", {"cogs": Decimal("10")})

    def test_update_missing_row_raises(self) -> None:
        class StubCur:
            def __init__(self) -> None:
                self.rowcount = 0

            def fetchone(self) -> None:
                return None

            def execute(self, sql: str, args: tuple = ()) -> None:
                pass

            def __enter__(self) -> StubCur:
                return self

            def __exit__(self, *exc: object) -> None:
                pass

        class StubConn:
            def cursor(self) -> StubCur:
                return StubCur()

        store = DbStore(conn=StubConn(), columns={"sales_invoices": {"invoice_id", "cogs"}})
        with self.assertRaises(RowNotFound):
            store.update("sales_invoices", "INV1", {"cogs": Decimal("10")})

    def test_update_unknown_column_raises(self) -> None:
        store = DbStore(conn=None, columns={"sales_invoices": {"invoice_id", "cogs"}})
        with self.assertRaises(UnknownColumn):
            store.update("sales_invoices", "INV1", {"not_a_col": 1})


class RunLogAndReplayTests(unittest.TestCase):
    def test_save_page_then_replay(self) -> None:
        with TemporaryDirectory() as tmp:
            output_dir = Path(tmp)
            runlog = RunLog(output_dir, "20261021-020000")
            runlog.save_page(
                "invoices",
                "/invoices",
                {"last_modified_time_after": "t1", "page": 1},
                {"invoices": [{"invoice_id": "I1"}]},
            )
            runlog.save_page(
                "invoices",
                "/invoices",
                {"last_modified_time_after": "t1", "page": 2},
                {"invoices": [{"invoice_id": "I2"}]},
            )
            # page-N.json numbering is per dataset, starting at 1.
            self.assertTrue((runlog.run_folder / "invoices" / "page-1.json").exists())
            self.assertTrue((runlog.run_folder / "invoices" / "page-2.json").exists())

            replay = ReplayGateway(runlog.run_folder)
            first = replay.get("/invoices", {"last_modified_time_after": "t1", "page": 1})
            second = replay.get("/invoices", {"last_modified_time_after": "t1", "page": 2})
            self.assertEqual(first["invoices"][0]["invoice_id"], "I1")
            self.assertEqual(second["invoices"][0]["invoice_id"], "I2")

    def test_replay_missing_page_raises(self) -> None:
        with TemporaryDirectory() as tmp:
            output_dir = Path(tmp)
            runlog = RunLog(output_dir, "20261021-020000")
            runlog.save_page("invoices", "/invoices", {"page": 1}, {"invoices": []})
            replay = ReplayGateway(runlog.run_folder)
            with self.assertRaises(PageNotFound):
                replay.get("/invoices", {"page": 2})

    def test_replay_no_run_folder_raises(self) -> None:
        with TemporaryDirectory() as tmp:
            with self.assertRaises(PageNotFound):
                ReplayGateway(Path(tmp) / "nope")

    def test_summary_written(self) -> None:
        with TemporaryDirectory() as tmp:
            runlog = RunLog(Path(tmp), "20261021-020000")
            path = runlog.save_summary({"calls": 3, "rows_stored": 2})
            self.assertEqual(json.loads(path.read_text())["calls"], 3)

    def test_new_run_id_format(self) -> None:
        run_id = new_run_id(datetime(2026, 10, 21, 2, 0, 0))
        self.assertEqual(run_id, "20261021-020000")

    def test_cleanup_old_runs(self) -> None:
        with TemporaryDirectory() as tmp:
            output_dir = Path(tmp)
            old = RunLog(output_dir, "20250101-020000")
            old.save_summary({})
            recent = RunLog(output_dir, new_run_id(datetime(2026, 10, 20, 2, 0, 0)))
            recent.save_summary({})
            removed = cleanup_old_runs(output_dir, days=30, now=datetime(2026, 10, 21, 2, 0, 0))
            self.assertEqual(len(removed), 1)
            self.assertFalse(old.run_folder.exists())
            self.assertTrue(recent.run_folder.exists())


class CacheTests(unittest.TestCase):
    def test_write_then_read_is_bare(self) -> None:
        with TemporaryDirectory() as tmp:
            cache = Cache(Path(tmp))
            cache.write("invoices", "I1", {"invoice_id": "I1", "last_modified_time": "t1"})
            self.assertEqual(cache.read("invoices", "I1"), {"invoice_id": "I1", "last_modified_time": "t1"})

    def test_read_unwraps_old_envelope(self) -> None:
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "invoices" / "I1.json"
            path.parent.mkdir(parents=True)
            path.write_text(
                json.dumps({"code": 0, "message": "success", "invoice": {"invoice_id": "I1", "last_modified_time": "t1"}})
            )
            cache = Cache(Path(tmp))
            self.assertEqual(cache.read("invoices", "I1"), {"invoice_id": "I1", "last_modified_time": "t1"})

    def test_missing_file_reads_none(self) -> None:
        with TemporaryDirectory() as tmp:
            cache = Cache(Path(tmp))
            self.assertIsNone(cache.read("invoices", "I1"))

    def test_is_current(self) -> None:
        with TemporaryDirectory() as tmp:
            cache = Cache(Path(tmp))
            cache.write("invoices", "I1", {"invoice_id": "I1", "last_modified_time": "t1"})
            self.assertTrue(cache.is_current("invoices", "I1", "t1"))
            self.assertFalse(cache.is_current("invoices", "I1", "t2"))
            self.assertFalse(cache.is_current("invoices", "I2", "t1"))

    def test_write_is_atomic_no_tmp_left_behind(self) -> None:
        with TemporaryDirectory() as tmp:
            cache = Cache(Path(tmp))
            cache.write("invoices", "I1", {"invoice_id": "I1"})
            self.assertFalse(cache.path("invoices", "I1").with_suffix(".json.tmp").exists())


class BudgetTests(unittest.TestCase):
    def test_no_wait_below_interval_zero(self) -> None:
        with TemporaryDirectory() as tmp:
            budget = Budget(Path(tmp) / "stamp", interval=0)
            slept = []
            budget._sleep = slept.append  # interval 0 should never call this
            budget.before_call()
            budget.before_call()
            self.assertEqual(slept, [])
            self.assertEqual(budget.calls_made, 2)

    def test_paces_calls(self) -> None:
        with TemporaryDirectory() as tmp:
            clock = [100.0]
            slept = []

            def fake_now() -> float:
                return clock[0]

            def fake_sleep(seconds: float) -> None:
                slept.append(seconds)
                clock[0] += seconds

            budget = Budget(Path(tmp) / "stamp", interval=20.0, now=fake_now, sleep=fake_sleep)
            budget.before_call()  # first call, nothing to wait for
            clock[0] += 5  # only 5s elapsed before the next call
            budget.before_call()
            self.assertEqual(slept, [15.0])

    def test_max_calls_raises(self) -> None:
        with TemporaryDirectory() as tmp:
            budget = Budget(Path(tmp) / "stamp", interval=0, max_calls=1)
            budget.before_call()
            with self.assertRaises(BudgetExceeded):
                budget.before_call()

    def test_stamp_file_shared_across_instances(self) -> None:
        with TemporaryDirectory() as tmp:
            stamp = Path(tmp) / "stamp"
            clock = [100.0]
            slept = []

            def fake_now() -> float:
                return clock[0]

            def fake_sleep(seconds: float) -> None:
                slept.append(seconds)
                clock[0] += seconds

            a = Budget(stamp, interval=20.0, now=fake_now, sleep=fake_sleep)
            b = Budget(stamp, interval=20.0, now=fake_now, sleep=fake_sleep)
            a.before_call()
            clock[0] += 2
            b.before_call()  # a different Budget instance, same stamp file
            self.assertEqual(slept, [18.0])


class RangesTests(unittest.TestCase):
    def test_format_and_parse_pending_doc_id_round_trip(self) -> None:
        r = DateRange(date(2026, 9, 28), date(2026, 10, 3))
        self.assertEqual(format_range_doc_id(r), "2026-09-28..2026-10-03")
        self.assertEqual(parse_pending_doc_id("2026-09-28..2026-10-03"), r)

    def test_trailing_window_spans_prev_month_5th_to_today(self) -> None:
        window = trailing_window(date(2026, 10, 21))
        self.assertEqual(window, DateRange(date(2026, 9, 5), date(2026, 10, 21)))

    def test_trailing_window_handles_short_previous_month(self) -> None:
        window = trailing_window(date(2026, 3, 3))
        self.assertEqual(window, DateRange(date(2026, 2, 5), date(2026, 3, 3)))

    def test_merge_ranges_joins_overlapping_and_adjacent(self) -> None:
        ranges = [
            DateRange(date(2026, 1, 1), date(2026, 1, 5)),
            DateRange(date(2026, 1, 6), date(2026, 1, 10)),  # adjacent
            DateRange(date(2026, 1, 3), date(2026, 1, 4)),  # overlapping
            DateRange(date(2026, 2, 1), date(2026, 2, 2)),  # disjoint
        ]
        self.assertEqual(
            merge_ranges(ranges),
            [DateRange(date(2026, 1, 1), date(2026, 1, 10)), DateRange(date(2026, 2, 1), date(2026, 2, 2))],
        )

    def test_merge_ranges_empty(self) -> None:
        self.assertEqual(merge_ranges([]), [])

    def test_cost_of_sales_ranges_non_02_run_uses_only_invoice_dates(self) -> None:
        result = cost_of_sales_ranges(
            invoice_dates=[date(2026, 10, 5), date(2026, 10, 6)],
            today=date(2026, 10, 21),
            hour=14,
            changed_bill_dates=[date(2026, 9, 1)],
            pending_doc_ids=[],
        )
        self.assertEqual(result, [DateRange(date(2026, 10, 5), date(2026, 10, 6))])

    def test_cost_of_sales_ranges_02_run_adds_trailing_window_and_bill_ranges(self) -> None:
        result = cost_of_sales_ranges(
            invoice_dates=[],
            today=date(2026, 10, 21),
            hour=2,
            changed_bill_dates=[date(2026, 10, 1)],
            pending_doc_ids=[],
        )
        # trailing window (2026-09-05..2026-10-21) already covers the bill range.
        self.assertEqual(result, [DateRange(date(2026, 9, 5), date(2026, 10, 21))])

    def test_cost_of_sales_ranges_02_run_bill_range_outside_window(self) -> None:
        result = cost_of_sales_ranges(
            invoice_dates=[],
            today=date(2026, 10, 21),
            hour=2,
            changed_bill_dates=[date(2026, 6, 1)],
            pending_doc_ids=[],
        )
        self.assertEqual(
            result,
            [DateRange(date(2026, 6, 1), date(2026, 10, 21))],
        )

    def test_cost_of_sales_ranges_includes_pending_ranges(self) -> None:
        result = cost_of_sales_ranges(
            invoice_dates=[date(2026, 1, 1)],
            today=date(2026, 10, 21),
            hour=14,
            changed_bill_dates=[],
            pending_doc_ids=["2026-01-02..2026-01-03"],
        )
        self.assertEqual(result, [DateRange(date(2026, 1, 1), date(2026, 1, 3))])


class MasterEnsureTests(unittest.TestCase):
    def test_customer_ensure_does_not_write_vendor(self) -> None:
        contact = _load_fixture("contact_customer.json")
        cid = contact["contact_id"]
        gw = FakeGateway()
        gw.add(f"/contacts/{cid}", None, {"contact": contact})
        with TemporaryDirectory() as tmp:
            run = _test_run(gw, cache_root=Path(tmp))
            ensure(run, "customer", cid)
            self.assertTrue(run.store.has("customers", cid))
            self.assertFalse(run.store.has("vendors", cid))
            self.assertEqual(run.cache.read("contacts", cid)["contact_type"], "customer")

    def test_vendor_ensure_does_not_write_customer(self) -> None:
        contact = _load_fixture("contact_vendor.json")
        cid = contact["contact_id"]
        gw = FakeGateway()
        gw.add(f"/contacts/{cid}", None, {"contact": contact})
        with TemporaryDirectory() as tmp:
            run = _test_run(gw, cache_root=Path(tmp))
            ensure(run, "vendor", cid)
            self.assertTrue(run.store.has("vendors", cid))
            self.assertFalse(run.store.has("customers", cid))

    def test_customer_wrong_type_writes_nothing(self) -> None:
        contact = _load_fixture("contact_vendor.json")
        cid = contact["contact_id"]
        gw = FakeGateway()
        gw.add(f"/contacts/{cid}", None, {"contact": contact})
        with TemporaryDirectory() as tmp:
            run = _test_run(gw, cache_root=Path(tmp))
            with self.assertRaises(WrongType):
                ensure(run, "customer", cid)
            self.assertFalse(run.store.has("customers", cid))
            self.assertFalse(run.store.has("vendors", cid))

    def test_memo_and_store_skip_second_call(self) -> None:
        contact = _load_fixture("contact_customer.json")
        cid = contact["contact_id"]
        gw = FakeGateway()
        gw.add(f"/contacts/{cid}", None, {"contact": contact})
        with TemporaryDirectory() as tmp:
            run = _test_run(gw, cache_root=Path(tmp))
            ensure(run, "customer", cid)
            ensure(run, "customer", cid)
            self.assertEqual(len(gw.calls), 1)

    def test_account_ensures_parent_first(self) -> None:
        child = _load_fixture("account_child.json")
        parent = _load_fixture("account_parent.json")
        gw = FakeGateway()
        gw.add(f"/chartofaccounts/{child['account_id']}", None, {"chart_of_account": child})
        gw.add(f"/chartofaccounts/{parent['account_id']}", None, {"chart_of_account": parent})
        with TemporaryDirectory() as tmp:
            run = _test_run(gw, cache_root=Path(tmp))
            ensure(run, "account", child["account_id"])
            self.assertTrue(run.store.has("accounts", parent["account_id"]))
            self.assertTrue(run.store.has("accounts", child["account_id"]))
            # parent fetched before child is written: first call is child GET, second parent
            self.assertEqual(
                [c[0] for c in gw.calls],
                [f"/chartofaccounts/{child['account_id']}", f"/chartofaccounts/{parent['account_id']}"],
            )
            # MIS columns stay put when ensure upserts Zoho columns only.
            run.store.upsert(
                "accounts",
                [{"account_id": child["account_id"], "category": "kept", "pl_bs": "pl"}],
            )
            run.master_memo.clear()
            ensure(run, "account", child["account_id"])
            stored = run.store.get("accounts", child["account_id"])
            self.assertEqual(stored["category"], "kept")
            self.assertEqual(stored["pl_bs"], "pl")

    def test_item_ensures_accounts_and_writes_units(self) -> None:
        item = _load_fixture("item_detail.json")
        sales = _load_fixture(f"account_{item['account_id']}.json")
        cogs = _load_fixture(f"account_{item['purchase_account_id']}.json")
        sales_parent = _load_fixture(f"account_{sales['parent_account_id']}.json")
        cogs_parent = _load_fixture(f"account_{cogs['parent_account_id']}.json")
        gw = FakeGateway()
        gw.add(f"/items/{item['item_id']}", None, {"item": item})
        for acc in (sales, cogs, sales_parent, cogs_parent):
            gw.add(f"/chartofaccounts/{acc['account_id']}", None, {"chart_of_account": acc})
        with TemporaryDirectory() as tmp:
            run = _test_run(gw, cache_root=Path(tmp))
            ensure(run, "item", item["item_id"])
            self.assertTrue(run.store.has("items", item["item_id"]))
            self.assertTrue(run.store.has("accounts", item["account_id"]))
            self.assertTrue(run.store.has("accounts", item["purchase_account_id"]))
            units = [
                row
                for row in run.store._tables.get("item_units", {}).values()
                if row["item_id"] == item["item_id"]
            ]
            self.assertEqual(len(units), 2)
            self.assertNotIn("raw_json", run.store.get("items", item["item_id"]))

    def test_location_uses_list_and_writes_only_matching_id(self) -> None:
        body = _load_fixture("locations_list.json")
        target = body["locations"][0]["location_id"]
        gw = FakeGateway()
        gw.add("/locations", None, body)
        with TemporaryDirectory() as tmp:
            run = _test_run(gw, cache_root=Path(tmp))
            ensure(run, "location", target)
            self.assertTrue(run.store.has("locations", target))
            self.assertFalse(run.store.has("locations", "LOC2"))
            self.assertEqual(gw.calls, [("/locations", None)])

    def test_salesperson_falls_back_to_list(self) -> None:
        body = _load_fixture("salespersons_list.json")
        gw = FakeGateway()
        gw.add("/salespersons/SP2", None, NotFound("no id route"))
        gw.add("/salespersons", None, body)
        with TemporaryDirectory() as tmp:
            run = _test_run(gw, cache_root=Path(tmp))
            ensure(run, "salesperson", "SP2")
            self.assertEqual(run.store.get("salespersons", "SP2")["salesperson_name"], "YOONUS")
            self.assertEqual([c[0] for c in gw.calls], ["/salespersons/SP2", "/salespersons"])


_INVOICE_LIST_ROW = {
    "invoice_id": "INV1", "invoice_number": "INV-001", "date": "2026-10-01",
    "due_date": "2026-10-15", "status": "closed", "customer_id": "C1",
    "customer_name": "Acme", "salesperson_id": "SP1", "salesperson_name": "Sam",
    "location_id": "L1", "location_name": "HQ", "currency_code": "AED",
    "exchange_rate": "1", "total": "110", "balance": "0", "shipping_charge": "0",
    "adjustment": "0", "last_modified_time": "2026-10-01T10:00:00+0400",
}
_INVOICE_DETAIL = {
    **_INVOICE_LIST_ROW,
    "sub_total": "100", "discount_total": "0", "tax_total": "10",
    "line_items": [{
        "line_item_id": "LI1", "item_id": "IT1", "quantity": "2", "rate": "50",
        "item_total": "100", "purchase_price": "20", "unit": "pcs", "base_unit": "pcs",
    }],
}


class SpecsTests(unittest.TestCase):
    """Every `DocSpec` maps its own fixture through its three mappers alone
    (task list, section 10): no store, no gateway."""

    def test_every_spec_has_consistent_run_order_and_mappers(self) -> None:
        self.assertEqual(
            [s.dataset for s in ALL_SPECS],
            ["debit_notes", "invoices", "bills", "vendor_credits", "sales_orders", "purchase_orders", "vendor_payments"],
        )
        for spec in ALL_SPECS:
            self.assertTrue(callable(spec.header_from_list))
            self.assertTrue(callable(spec.from_detail))
            self.assertTrue(callable(spec.collect_ids))

    def test_invoice_header_from_list_excludes_detail_only_columns(self) -> None:
        patch = INVOICES.header_from_list(_INVOICE_LIST_ROW)
        self.assertEqual(patch["invoice_id"], "INV1")
        self.assertNotIn("sub_total", patch)
        self.assertNotIn("net_sales", patch)
        self.assertNotIn("cogs", patch)

    def test_invoice_from_detail_builds_lines_and_net_sales(self) -> None:
        header_patch, lines = INVOICES.from_detail(_INVOICE_DETAIL, {}, {})
        self.assertEqual(header_patch["net_sales"], lines[0]["net_sales"])
        self.assertNotIn("cogs", header_patch)
        self.assertEqual(lines[0]["invoice_id"], "INV1")
        self.assertNotIn("baseline_cogs", lines[0])

    def test_invoice_collect_ids(self) -> None:
        ids = INVOICES.collect_ids(_INVOICE_DETAIL)
        self.assertEqual(ids, {"customer": {"C1"}, "salesperson": {"SP1"}, "location": {"L1"}, "item": {"IT1"}})

    def test_debit_note_renames_invoice_id_and_discount_column(self) -> None:
        doc = {**_INVOICE_DETAIL, "reference_invoice_id": "INV1", "reference_number": "DN-REF"}
        header_patch, lines = DEBIT_NOTES.from_detail(doc, {}, {})
        self.assertEqual(header_patch["debit_note_id"], "INV1")
        self.assertEqual(header_patch["reference_invoice_id"], "INV1")
        self.assertEqual(lines[0]["debit_note_id"], "INV1")
        self.assertIn("note_discount", lines[0])
        self.assertNotIn("invoice_discount", lines[0])
        self.assertNotIn("invoice_id", lines[0])

    def test_bill_header_from_list_sets_kind_and_doc_id(self) -> None:
        row = {"bill_id": "B1", "bill_number": "BILL-1", "vendor_id": "V1", "vendor_name": "Vendor",
               "status": "open", "date": "2026-10-01", "reference_number": "REF1"}
        patch = BILLS.header_from_list(row)
        self.assertEqual((patch["kind"], patch["doc_id"]), ("bill", "B1"))

    def test_bill_from_detail_lines_have_no_cogs_column(self) -> None:
        doc = {
            "bill_id": "B1", "vendor_id": "V1", "date": "2026-10-01",
            "sub_total": "45", "discount_total": "0", "tax_total": "5",
            "line_items": [{"line_item_id": "BL1", "item_id": "IT1", "quantity": "1", "rate": "45", "item_total": "45"}],
        }
        header_patch, lines = BILLS.from_detail(doc, {}, {})
        self.assertEqual((header_patch["kind"], header_patch["doc_id"]), ("bill", "B1"))
        self.assertNotIn("cogs", lines[0])
        self.assertIn("doc_discount", lines[0])

    def test_vendor_payment_bills_are_keyed_by_bill_payment_id(self) -> None:
        doc = {
            "payment_id": "P1", "vendor_id": "V1",
            "bills": [{"bill_payment_id": "BP1", "bill_id": "B1", "amount_applied": "50", "tax_amount_withheld": "0"}],
        }
        header_patch, lines = VENDOR_PAYMENTS.from_detail(doc, {}, {})
        self.assertEqual(header_patch["payment_id"], "P1")
        self.assertEqual(lines, [{
            "bill_payment_id": "BP1", "payment_id": "P1", "kind": "bill",
            "bill_id": "B1", "amount_applied": Decimal("50"), "tax_amount_withheld": Decimal("0"),
        }])

    def test_vendor_payment_collect_ids_has_no_item_lines(self) -> None:
        doc = {"payment_id": "P1", "vendor_id": "V1", "paid_through_account_id": "A1", "bills": []}
        self.assertEqual(VENDOR_PAYMENTS.collect_ids(doc), {"vendor": {"V1"}, "account": {"A1"}})

    def test_sales_order_header_from_list_maps_salesorder_fields(self) -> None:
        row = {
            "salesorder_id": "SO1", "salesorder_number": "SO-001",
            "customer_id": "C1", "customer_name": "Acme",
            "status": "open", "date": "2026-10-01", "total": "100",
        }
        patch = SALES_ORDERS.header_from_list(row)
        self.assertEqual(patch["salesorder_id"], "SO1")
        self.assertEqual(patch["salesorder_number"], "SO-001")
        self.assertNotIn("invoice_id", patch)

    def test_every_docspec_maps_fixture_through_three_mappers(self) -> None:
        """Every DocSpec maps its fixture through header_from_list / from_detail / collect_ids alone."""
        fixtures: dict[str, tuple[dict, dict]] = {
            "debit_notes": (
                {**_INVOICE_LIST_ROW, "invoice_id": "DN1", "invoice_number": "DN-1", "type": "debit_note"},
                {
                    **_INVOICE_DETAIL, "invoice_id": "DN1", "invoice_number": "DN-1", "type": "debit_note",
                    "reference_invoice_id": "INV1",
                },
            ),
            "invoices": (_INVOICE_LIST_ROW, _INVOICE_DETAIL),
            "bills": (
                {
                    "bill_id": "B1", "bill_number": "BILL-1", "vendor_id": "V1", "vendor_name": "Vendor",
                    "status": "open", "date": "2026-10-01", "last_modified_time": WM,
                },
                {
                    "bill_id": "B1", "vendor_id": "V1", "date": "2026-10-01",
                    "sub_total": "45", "discount_total": "0", "tax_total": "5",
                    "line_items": [{
                        "line_item_id": "BL1", "item_id": "IT1", "quantity": "1",
                        "rate": "45", "item_total": "45",
                    }],
                },
            ),
            "vendor_credits": (
                {
                    "vendor_credit_id": "VC1", "vendor_credit_number": "VC-1", "vendor_id": "V1",
                    "vendor_name": "Vendor", "status": "open", "date": "2026-10-01",
                    "bill_id": "B1", "last_modified_time": WM,
                },
                {
                    "vendor_credit_id": "VC1", "vendor_id": "V1", "date": "2026-10-01", "bill_id": "B1",
                    "sub_total": "10", "discount_total": "0", "tax_total": "0",
                    "line_items": [{
                        "line_item_id": "VCL1", "item_id": "IT1", "quantity": "1",
                        "rate": "10", "item_total": "10",
                    }],
                },
            ),
            "sales_orders": (
                {
                    "salesorder_id": "SO1", "salesorder_number": "SO-1", "customer_id": "C1",
                    "customer_name": "Acme", "status": "open", "date": "2026-10-01",
                    "last_modified_time": WM,
                },
                {
                    "salesorder_id": "SO1", "customer_id": "C1", "date": "2026-10-01",
                    "sub_total": "10", "discount_total": "0", "tax_total": "0",
                    "line_items": [{
                        "line_item_id": "SOL1", "item_id": "IT1", "quantity": "1",
                        "rate": "10", "item_total": "10", "quantity_invoiced": "0",
                    }],
                },
            ),
            "purchase_orders": (
                {
                    "purchaseorder_id": "PO1", "purchaseorder_number": "PO-1", "vendor_id": "V1",
                    "vendor_name": "Vendor", "status": "open", "date": "2026-10-01",
                    "last_modified_time": WM,
                },
                {
                    "purchaseorder_id": "PO1", "vendor_id": "V1", "date": "2026-10-01",
                    "sub_total": "10", "discount_total": "0", "tax_total": "0",
                    "line_items": [{
                        "line_item_id": "POL1", "item_id": "IT1", "quantity": "1",
                        "rate": "10", "item_total": "10",
                    }],
                },
            ),
            "vendor_payments": (
                {
                    "payment_id": "P1", "payment_number": "VP-1", "vendor_id": "V1",
                    "vendor_name": "Vendor", "date": "2026-10-01", "last_modified_time": WM,
                },
                {
                    "payment_id": "P1", "vendor_id": "V1",
                    "bills": [{
                        "bill_payment_id": "BP1", "bill_id": "B1",
                        "amount_applied": "50", "tax_amount_withheld": "0",
                    }],
                },
            ),
        }
        self.assertEqual(set(fixtures), {s.dataset for s in ALL_SPECS})
        for spec in ALL_SPECS:
            list_row, detail = fixtures[spec.dataset]
            header = spec.header_from_list(list_row)
            self.assertIsInstance(header, dict)
            self.assertTrue(header)
            patch, lines = spec.from_detail(detail, {}, {})
            self.assertIsInstance(patch, dict)
            self.assertIsInstance(lines, list)
            ids = spec.collect_ids(detail)
            self.assertIsInstance(ids, dict)
            self.assertIn(spec.party.split("_")[0], ids)  # customer / vendor


_COS_ACCOUNT = cogs.COS_ACCOUNT_ID


def _postings_params(date_str: str, page: int = 1) -> dict:
    return {
        "account_id": _COS_ACCOUNT, "per_page": 200,
        "date_start": date_str, "date_end": date_str, "page": page,
    }


class PostingsTests(unittest.TestCase):
    """Task 7, bullet 2: `postings.pull_range` through `account_postings.fetch_pages`,
    into `gl_journals` via `store.replace_range`. No network, no database."""

    def test_pulls_every_page_and_strips_raw_json(self) -> None:
        gw = FakeGateway()
        gw.add("/chartofaccounts/transactions", _postings_params("2026-10-01", 1), {
            "transactions": [{
                "account_id": _COS_ACCOUNT, "categorized_transaction_id": "CT1", "transaction_id": "INV1",
                "transaction_type": "inventory_valuation_for_invoice", "transaction_date": "2026-10-01",
                "debit_amount": "30", "credit_amount": "0",
            }],
            "page_context": {"account_name": "Cost of Sales - Nellon", "account_code": "5.1.1000", "has_more_page": True},
        })
        gw.add("/chartofaccounts/transactions", _postings_params("2026-10-01", 2), {
            "transactions": [{
                "account_id": _COS_ACCOUNT, "categorized_transaction_id": "CT2", "transaction_id": "INV2",
                "transaction_type": "inventory_valuation_for_invoice", "transaction_date": "2026-10-01",
                "debit_amount": "12", "credit_amount": "0",
            }],
            "page_context": {"account_name": "Cost of Sales - Nellon", "account_code": "5.1.1000", "has_more_page": False},
        })
        run = _test_run(gw)
        ok = postings.pull_range(run, _COS_ACCOUNT, DateRange(date(2026, 10, 1), date(2026, 10, 1)))
        self.assertTrue(ok)
        rows = run.store.gl_journal_rows()
        self.assertEqual({r["categorized_transaction_id"] for r in rows}, {"CT1", "CT2"})
        self.assertTrue(all(r["raw_json"] is None for r in rows))
        self.assertTrue(all(r["transaction_date"] == date(2026, 10, 1) for r in rows))
        self.assertEqual(run.store.list_pending("cogs"), [])

    def test_replaced_posting_is_not_double_counted(self) -> None:
        store = MemoryStore()
        store.replace_range(_COS_ACCOUNT, date(2026, 10, 1), date(2026, 10, 1), [
            {"account_id": _COS_ACCOUNT, "categorized_transaction_id": "OLD", "transaction_id": "INV1",
             "transaction_type": "inventory_valuation_for_invoice", "transaction_date": date(2026, 10, 1),
             "amount": "30"},
        ])
        gw = FakeGateway()
        gw.add("/chartofaccounts/transactions", _postings_params("2026-10-01", 1), {
            "transactions": [{
                "account_id": _COS_ACCOUNT, "categorized_transaction_id": "NEW", "transaction_id": "INV1",
                "transaction_type": "inventory_valuation_for_invoice", "transaction_date": "2026-10-01",
                "debit_amount": "31", "credit_amount": "0",
            }],
            "page_context": {"account_code": "5.1.1000", "has_more_page": False},
        })
        run = _test_run(gw, store=store)
        postings.pull_range(run, _COS_ACCOUNT, DateRange(date(2026, 10, 1), date(2026, 10, 1)))
        rows = store.gl_journal_rows()
        self.assertEqual([r["categorized_transaction_id"] for r in rows], ["NEW"])

    def test_failed_pull_records_pending_and_leaves_gl_journals(self) -> None:
        gw = FakeGateway()  # no fixture registered -> PageNotFound on the gateway call
        run = _test_run(gw)
        ok = postings.pull_range(run, _COS_ACCOUNT, DateRange(date(2026, 10, 2), date(2026, 10, 2)))
        self.assertFalse(ok)
        self.assertEqual(run.store.gl_journal_rows(), [])
        pending = run.store.list_pending("cogs")
        self.assertEqual(len(pending), 1)
        self.assertEqual(pending[0]["doc_id"], "2026-10-02..2026-10-02")


class CogsWiringTests(unittest.TestCase):
    """Task 7, bullets 2-3: `cogs.write_invoice_cogs` / `write_debit_note_cogs`
    write header/line COGS per the plan's table, through `store` only."""

    def _invoice_store(self) -> MemoryStore:
        store = MemoryStore()
        store.upsert("sales_lines", [
            {"line_item_id": "L1", "invoice_id": "INV1", "cogs": Decimal("10"),
             "baseline_cogs": Decimal("10"), "net_sales": Decimal("20")},
            {"line_item_id": "L2", "invoice_id": "INV1", "cogs": Decimal("10"),
             "baseline_cogs": Decimal("10"), "net_sales": Decimal("20")},
        ])
        store.upsert("sales_invoices", [{"invoice_id": "INV1", "status": "closed"}])
        return store

    def test_posted_with_postings_spreads_header_total_over_lines(self) -> None:
        store = self._invoice_store()
        store.replace_range(cogs.COS_ACCOUNT_ID, date(2026, 10, 1), date(2026, 10, 1), [
            {"account_id": cogs.COS_ACCOUNT_ID, "categorized_transaction_id": "CT1", "transaction_id": "INV1",
             "transaction_type": "inventory_valuation_for_invoice", "transaction_date": date(2026, 10, 1),
             "amount": "30"},
        ])
        now = datetime(2026, 10, 21, 2, 0, 0)
        cogs.write_invoice_cogs(store, cogs.COS_ACCOUNT_ID, [{"invoice_id": "INV1", "status": "closed"}], now)
        invoice = store.get("sales_invoices", "INV1")
        self.assertEqual(invoice["cogs"], Decimal("30.00"))
        self.assertEqual(invoice["cogs_synced_at"], now)
        lines = [store.get("sales_lines", "L1"), store.get("sales_lines", "L2")]
        self.assertEqual(sum(ln["cogs"] for ln in lines), Decimal("30.00"))

    def test_posted_with_no_postings_takes_sum_of_own_cost(self) -> None:
        store = self._invoice_store()
        cogs.write_invoice_cogs(
            store, cogs.COS_ACCOUNT_ID, [{"invoice_id": "INV1", "status": "closed"}], datetime(2026, 10, 21, 2, 0, 0)
        )
        invoice = store.get("sales_invoices", "INV1")
        self.assertEqual(invoice["cogs"], Decimal("20.00"))
        self.assertIsNotNone(invoice["cogs_synced_at"])

    def test_own_cost_uses_mapper_rules_when_baseline_is_not_stored(self) -> None:
        # Stored rows have no baseline_cogs: the rebuilt cost must match seed_common.line_cogs.
        store = MemoryStore()
        store.upsert("items", [
            {"item_id": "I1", "purchase_rate": Decimal("5")},
            {"item_id": "I2", "purchase_rate": Decimal("2")},
        ])
        store.upsert("sales_lines", [
            # price 0 -> master rate * base quantity (2 * 5)
            {"line_item_id": "L1", "invoice_id": "INV1", "item_id": "I1", "quantity": Decimal("2"),
             "conversion_rate": Decimal("1"), "base_quantity": Decimal("2"), "base_unit": "pc",
             "purchase_price": Decimal("0")},
            # price 24 is ~conv x master rate (a pack price): 3 packs * 24; multiplying by conv again would overstate
            {"line_item_id": "L2", "invoice_id": "INV1", "item_id": "I2", "quantity": Decimal("3"),
             "conversion_rate": Decimal("12"), "base_quantity": Decimal("36"), "base_unit": "pc",
             "purchase_price": Decimal("24")},
        ])
        store.upsert("sales_invoices", [{"invoice_id": "INV1", "status": "closed"}])
        cogs.write_invoice_cogs(
            store, cogs.COS_ACCOUNT_ID, [{"invoice_id": "INV1", "status": "closed"}], datetime(2026, 10, 21, 2, 0, 0)
        )
        self.assertEqual(store.get("sales_lines", "L1")["cogs"], Decimal("10.00"))
        self.assertEqual(store.get("sales_lines", "L2")["cogs"], Decimal("72.00"))
        self.assertEqual(store.get("sales_invoices", "INV1")["cogs"], Decimal("82.00"))

    def test_void_invoice_gets_zero(self) -> None:
        store = self._invoice_store()
        store.upsert("sales_invoices", [{"invoice_id": "INV1", "status": "void"}], update_cols=["status"])
        cogs.write_invoice_cogs(
            store, cogs.COS_ACCOUNT_ID, [{"invoice_id": "INV1", "status": "void"}], datetime(2026, 10, 21, 2, 0, 0)
        )
        invoice = store.get("sales_invoices", "INV1")
        self.assertEqual(invoice["cogs"], Decimal("0.00"))
        self.assertEqual(store.get("sales_lines", "L1")["cogs"], Decimal("0.00"))

    def test_debit_note_takes_sum_of_own_cost_and_ignores_same_date_vendor_credit_posting(self) -> None:
        store = MemoryStore()
        store.upsert("debit_note_lines", [{"line_item_id": "D1", "debit_note_id": "DN1", "cogs": Decimal("5")}])
        store.upsert("debit_notes", [{"debit_note_id": "DN1", "status": "closed"}])
        # A vendor-credit inventory_valuation_for_debit_notes row on the same date must
        # never be matched to this customer debit note (plan, task 7, bullet 3/4).
        store.replace_range(cogs.COS_ACCOUNT_ID, date(2026, 10, 1), date(2026, 10, 1), [
            {"account_id": cogs.COS_ACCOUNT_ID, "categorized_transaction_id": "VC1", "transaction_id": "DN1",
             "transaction_type": "inventory_valuation_for_debit_notes", "transaction_date": date(2026, 10, 1),
             "amount": "999"},
        ])
        now = datetime(2026, 10, 21, 2, 0, 0)
        cogs.write_debit_note_cogs(store, [{"debit_note_id": "DN1", "status": "closed"}], now)
        note = store.get("debit_notes", "DN1")
        self.assertEqual(note["cogs"], Decimal("5.00"))
        self.assertEqual(note["cogs_synced_at"], now)
        self.assertEqual(store.get("debit_note_lines", "D1")["cogs"], Decimal("5"))

    def test_debit_note_draft_gets_zero(self) -> None:
        store = MemoryStore()
        store.upsert("debit_note_lines", [{"line_item_id": "D1", "debit_note_id": "DN1", "cogs": Decimal("5")}])
        store.upsert("debit_notes", [{"debit_note_id": "DN1", "status": "draft"}])
        cogs.write_debit_note_cogs(
            store, [{"debit_note_id": "DN1", "status": "draft"}], datetime(2026, 10, 21, 2, 0, 0)
        )
        self.assertEqual(store.get("debit_notes", "DN1")["cogs"], Decimal("0.00"))

    def test_second_cogs_pass_gives_identical_rows(self) -> None:
        store = MemoryStore()
        store.upsert("sales_lines", [
            {"line_item_id": "L1", "invoice_id": "INV1", "quantity": Decimal("2"),
             "purchase_price": Decimal("10"), "conversion_rate": Decimal("1"), "net_sales": Decimal("30")},
            {"line_item_id": "L2", "invoice_id": "INV1", "quantity": Decimal("1"),
             "purchase_price": Decimal("20"), "conversion_rate": Decimal("1"), "net_sales": Decimal("30")},
        ])
        store.upsert("sales_invoices", [{"invoice_id": "INV1", "status": "closed"}])
        store.replace_range(cogs.COS_ACCOUNT_ID, date(2026, 10, 1), date(2026, 10, 1), [
            {"account_id": cogs.COS_ACCOUNT_ID, "categorized_transaction_id": "CT1", "transaction_id": "INV1",
             "transaction_type": "inventory_valuation_for_invoice", "transaction_date": date(2026, 10, 1),
             "amount": "60"},
        ])
        now1 = datetime(2026, 10, 21, 2, 0, 0)
        cogs.write_invoice_cogs(store, cogs.COS_ACCOUNT_ID, [{"invoice_id": "INV1", "status": "closed"}], now1)
        first_inv = dict(store.get("sales_invoices", "INV1") or {})
        first_l1 = dict(store.get("sales_lines", "L1") or {})
        first_l2 = dict(store.get("sales_lines", "L2") or {})

        now2 = datetime(2026, 10, 22, 2, 0, 0)
        cogs.write_invoice_cogs(store, cogs.COS_ACCOUNT_ID, [{"invoice_id": "INV1", "status": "closed"}], now2)
        second_inv = dict(store.get("sales_invoices", "INV1") or {})
        second_l1 = dict(store.get("sales_lines", "L1") or {})
        second_l2 = dict(store.get("sales_lines", "L2") or {})

        self.assertEqual(first_inv["cogs"], second_inv["cogs"])
        self.assertEqual(first_l1["cogs"], second_l1["cogs"])
        self.assertEqual(first_l2["cogs"], second_l2["cogs"])

    def test_postings_disappear_falls_back_to_lines_own_cost(self) -> None:
        store = MemoryStore()
        store.upsert("sales_lines", [
            {"line_item_id": "L1", "invoice_id": "INV1", "quantity": Decimal("2"),
             "purchase_price": Decimal("10"), "conversion_rate": Decimal("1"), "net_sales": Decimal("30")},
            {"line_item_id": "L2", "invoice_id": "INV1", "quantity": Decimal("1"),
             "purchase_price": Decimal("20"), "conversion_rate": Decimal("1"), "net_sales": Decimal("30")},
        ])
        store.upsert("sales_invoices", [{"invoice_id": "INV1", "status": "closed"}])
        store.replace_range(cogs.COS_ACCOUNT_ID, date(2026, 10, 1), date(2026, 10, 1), [
            {"account_id": cogs.COS_ACCOUNT_ID, "categorized_transaction_id": "CT1", "transaction_id": "INV1",
             "transaction_type": "inventory_valuation_for_invoice", "transaction_date": date(2026, 10, 1),
             "amount": "60"},
        ])
        now = datetime(2026, 10, 21, 2, 0, 0)
        cogs.write_invoice_cogs(store, cogs.COS_ACCOUNT_ID, [{"invoice_id": "INV1", "status": "closed"}], now)
        self.assertEqual(store.get("sales_invoices", "INV1")["cogs"], Decimal("60.00"))

        store.replace_range(cogs.COS_ACCOUNT_ID, date(2026, 10, 1), date(2026, 10, 1), [])
        cogs.write_invoice_cogs(store, cogs.COS_ACCOUNT_ID, [{"invoice_id": "INV1", "status": "closed"}], now)

        inv = store.get("sales_invoices", "INV1")
        self.assertEqual(inv["cogs"], Decimal("40.00"))
        self.assertEqual(store.get("sales_lines", "L1")["cogs"], Decimal("20.00"))
        self.assertEqual(store.get("sales_lines", "L2")["cogs"], Decimal("20.00"))


class CostOfSalesPipelineTests(unittest.TestCase):
    """Task 7 wired into `pipeline.run_all` / `run_cost_of_sales` (plan, "Step 3
    — Cost of Sales pass"): runs once, after every dataset above has listed."""

    def test_run_all_skips_cost_of_sales_when_no_spec_has_cogs(self) -> None:
        store = MemoryStore()
        store.set_watermark("bills", "2020-01-01T00:00:00+0400")
        gw = FakeGateway()
        gw.add(
            "/bills",
            {"last_modified_time": "2020-01-01T00:00:00+0400", "page": 1, "per_page": 200},
            {"bills": [], "page_context": {"has_more_page": False}},
        )
        run = _test_run(gw, store=store)
        summary = pipeline.run_all(run, specs=(BILLS,))
        self.assertNotIn("cost_of_sales", summary)
        # No postings endpoint was ever called.
        self.assertTrue(all(c[0] == "/bills" for c in gw.calls))

    def test_run_cost_of_sales_pulls_range_and_reconciles_claimed_invoice(self) -> None:
        store = MemoryStore()
        store.upsert("sales_invoices", [{"invoice_id": "INV1", "status": "closed", "date": date(2026, 10, 1)}])
        store.upsert("sales_lines", [
            {"line_item_id": "L1", "invoice_id": "INV1", "cogs": Decimal("10"),
             "baseline_cogs": Decimal("10"), "net_sales": Decimal("20")},
        ])
        gw = FakeGateway()
        gw.add("/chartofaccounts/transactions", _postings_params("2026-10-01", 1), {
            "transactions": [{
                "account_id": _COS_ACCOUNT, "categorized_transaction_id": "CT1", "transaction_id": "INV1",
                "transaction_type": "inventory_valuation_for_invoice", "transaction_date": "2026-10-01",
                "debit_amount": "11", "credit_amount": "0",
            }],
            "page_context": {"account_code": "5.1.1000", "has_more_page": False},
        })
        run = _test_run(gw, store=store)
        run.clock = lambda: datetime(2026, 10, 1, 21, 0, 0)
        stats = pipeline.run_cost_of_sales(run, {"invoices": {"INV1"}})
        self.assertEqual(stats["ranges_pulled"], 1)
        self.assertEqual(stats["invoices_reconciled"], 1)
        self.assertEqual(store.get("sales_invoices", "INV1")["cogs"], Decimal("11.00"))
        self.assertEqual(store.get("sales_lines", "L1")["cogs"], Decimal("11.00"))

    def test_run_cost_of_sales_reconciles_debit_note_with_no_gateway_call(self) -> None:
        store = MemoryStore()
        store.upsert("debit_note_lines", [{"line_item_id": "D1", "debit_note_id": "DN1", "cogs": Decimal("4")}])
        store.upsert("debit_notes", [{"debit_note_id": "DN1", "status": "closed"}])
        gw = FakeGateway()
        run = _test_run(gw, store=store)
        run.clock = lambda: datetime(2026, 10, 1, 21, 0, 0)
        stats = pipeline.run_cost_of_sales(run, {"debit_notes": {"DN1"}})
        self.assertEqual(stats["ranges_attempted"], 0)
        self.assertEqual(stats["debit_notes_reconciled"], 1)
        self.assertEqual(store.get("debit_notes", "DN1")["cogs"], Decimal("4.00"))
        self.assertEqual(gw.calls, [])

    def test_failed_postings_pull_leaves_cogs_and_records_pending(self) -> None:
        store = MemoryStore()
        store.upsert("sales_invoices", [{"invoice_id": "INV1", "status": "closed", "date": date(2026, 10, 2)}])
        gw = FakeGateway()  # no fixture -> the pull fails
        run = _test_run(gw, store=store)
        run.clock = lambda: datetime(2026, 10, 2, 21, 0, 0)
        stats = pipeline.run_cost_of_sales(run, {"invoices": {"INV1"}})
        self.assertEqual(stats["ranges_pulled"], 0)
        self.assertEqual(stats["invoices_reconciled"], 0)
        self.assertEqual(store.get("sales_invoices", "INV1").get("cogs", Decimal("0.00")), Decimal("0.00"))
        self.assertEqual(len(store.list_pending("cogs")), 1)

    def test_changed_bill_on_02_run_repulls_from_bill_date_to_today(self) -> None:
        store = MemoryStore()
        store.upsert("purchase_docs", [{
            "kind": "bill", "doc_id": "B1", "date": date(2026, 9, 1), "status": "open",
        }])
        params = {
            "account_id": _COS_ACCOUNT, "per_page": 200,
            "date_start": "2026-09-01", "date_end": "2026-10-21", "page": 1,
        }
        gw = FakeGateway()
        gw.add("/chartofaccounts/transactions", params, {
            "transactions": [{
                "account_id": _COS_ACCOUNT, "categorized_transaction_id": "CTB",
                "transaction_id": "INV9", "transaction_type": "inventory_valuation_for_invoice",
                "transaction_date": "2026-09-15", "debit_amount": "7", "credit_amount": "0",
            }],
            "page_context": {"account_code": "5.1.1000", "has_more_page": False},
        })
        run = _test_run(gw, store=store)
        run.clock = lambda: datetime(2026, 10, 21, 2, 0, 0)
        stats = pipeline.run_cost_of_sales(run, {"bills": {"B1"}})
        self.assertEqual(stats["ranges_attempted"], 1)
        self.assertEqual(stats["ranges_pulled"], 1)
        self.assertEqual(
            [(c[0], c[1]["date_start"], c[1]["date_end"]) for c in gw.calls],
            [("/chartofaccounts/transactions", "2026-09-01", "2026-10-21")],
        )
        self.assertEqual(
            {r["categorized_transaction_id"] for r in store.gl_journal_rows()}, {"CTB"},
        )

    def test_vendor_credit_posting_stored_without_changing_invoice_or_debit_note_cogs(self) -> None:
        store = MemoryStore()
        store.upsert("sales_invoices", [{
            "invoice_id": "INV1", "status": "closed", "date": date(2026, 10, 1),
            "cogs": Decimal("11.00"), "cogs_synced_at": datetime(2026, 10, 1, 3, 0, 0),
        }])
        store.upsert("sales_lines", [{
            "line_item_id": "L1", "invoice_id": "INV1", "cogs": Decimal("11.00"),
            "baseline_cogs": Decimal("10"), "net_sales": Decimal("20"),
        }])
        store.upsert("debit_notes", [{
            "debit_note_id": "DN1", "status": "closed", "date": date(2026, 10, 1),
            "cogs": Decimal("4.00"), "cogs_synced_at": datetime(2026, 10, 1, 3, 0, 0),
        }])
        store.upsert("debit_note_lines", [{
            "line_item_id": "D1", "debit_note_id": "DN1", "cogs": Decimal("4"),
        }])
        gw = FakeGateway()
        gw.add("/chartofaccounts/transactions", _postings_params("2026-10-01", 1), {
            "transactions": [
                {
                    "account_id": _COS_ACCOUNT, "categorized_transaction_id": "CTINV",
                    "transaction_id": "INV1", "transaction_type": "inventory_valuation_for_invoice",
                    "transaction_date": "2026-10-01", "debit_amount": "11", "credit_amount": "0",
                },
                {
                    "account_id": _COS_ACCOUNT, "categorized_transaction_id": "VCPOST",
                    "transaction_id": "VC1", "transaction_type": "inventory_valuation_for_debit_notes",
                    "transaction_date": "2026-10-01", "debit_amount": "999", "credit_amount": "0",
                    "entry_number": "KGT-VC-0001",
                },
            ],
            "page_context": {"account_code": "5.1.1000", "has_more_page": False},
        })
        run = _test_run(gw, store=store)
        run.clock = lambda: datetime(2026, 10, 1, 21, 0, 0)
        stats = pipeline.run_cost_of_sales(run, {"invoices": {"INV1"}, "debit_notes": {"DN1"}})
        self.assertEqual(stats["ranges_pulled"], 1)
        rows = store.gl_journal_rows()
        self.assertEqual(
            {r["categorized_transaction_id"] for r in rows}, {"CTINV", "VCPOST"},
        )
        vc = next(r for r in rows if r["categorized_transaction_id"] == "VCPOST")
        self.assertEqual(vc["transaction_type"], "inventory_valuation_for_debit_notes")
        # Invoice matches only inventory_valuation_for_invoice; VC 999 is ignored.
        self.assertEqual(store.get("sales_invoices", "INV1")["cogs"], Decimal("11.00"))
        self.assertEqual(store.get("debit_notes", "DN1")["cogs"], Decimal("4.00"))
        self.assertEqual(store.get("sales_lines", "L1")["cogs"], Decimal("11.00"))
        self.assertEqual(store.get("debit_note_lines", "D1")["cogs"], Decimal("4"))

    def test_cost_of_sales_0159_run_crosses_0300_still_pulls_trailing_and_bill_ranges(self) -> None:
        store = MemoryStore()
        store.upsert("purchase_docs", [{
            "kind": "bill", "doc_id": "B1", "date": date(2026, 9, 1), "status": "open",
        }])
        params = {
            "account_id": _COS_ACCOUNT, "per_page": 200,
            "date_start": "2026-09-01", "date_end": "2026-10-21", "page": 1,
        }
        gw = FakeGateway()
        gw.add("/chartofaccounts/transactions", params, {
            "transactions": [], "page_context": {"account_code": "5.1.1000", "has_more_page": False},
        })
        run = _test_run(gw, store=store)
        from zoneinfo import ZoneInfo
        dubai = ZoneInfo("Asia/Dubai")
        run.started_at = datetime(2026, 10, 21, 1, 59, 0, tzinfo=dubai)
        run.clock = lambda: datetime(2026, 10, 21, 3, 5, 0, tzinfo=dubai)
        stats = pipeline.run_cost_of_sales(run, {"bills": {"B1"}})
        self.assertEqual(stats["ranges_attempted"], 1)
        self.assertEqual(
            [(c[0], c[1]["date_start"], c[1]["date_end"]) for c in gw.calls],
            [("/chartofaccounts/transactions", "2026-09-01", "2026-10-21")],
        )

    def test_cost_of_sales_0130_run_does_not_pull_trailing_or_bill_ranges(self) -> None:
        store = MemoryStore()
        store.upsert("purchase_docs", [{
            "kind": "bill", "doc_id": "B1", "date": date(2026, 9, 1), "status": "open",
        }])
        gw = FakeGateway()
        run = _test_run(gw, store=store)
        from zoneinfo import ZoneInfo
        dubai = ZoneInfo("Asia/Dubai")
        run.started_at = datetime(2026, 10, 21, 1, 30, 0, tzinfo=dubai)
        run.clock = lambda: datetime(2026, 10, 21, 1, 35, 0, tzinfo=dubai)
        stats = pipeline.run_cost_of_sales(run, {"bills": {"B1"}})
        self.assertEqual(stats["ranges_attempted"], 0)
        self.assertEqual(gw.calls, [])

    def test_cost_of_sales_0301_run_does_not_pull_trailing_or_bill_ranges(self) -> None:
        store = MemoryStore()
        store.upsert("purchase_docs", [{
            "kind": "bill", "doc_id": "B1", "date": date(2026, 9, 1), "status": "open",
        }])
        gw = FakeGateway()
        run = _test_run(gw, store=store)
        from zoneinfo import ZoneInfo
        dubai = ZoneInfo("Asia/Dubai")
        run.started_at = datetime(2026, 10, 21, 3, 1, 0, tzinfo=dubai)
        run.clock = lambda: datetime(2026, 10, 21, 3, 5, 0, tzinfo=dubai)
        stats = pipeline.run_cost_of_sales(run, {"bills": {"B1"}})
        self.assertEqual(stats["ranges_attempted"], 0)
        self.assertEqual(gw.calls, [])


class ReplayTests(unittest.TestCase):
    """`--replay` makes no network call and writes the same rows (task 10)."""

    def test_build_run_replay_uses_replay_gateway(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "runs" / "oldrun").mkdir(parents=True)
            with mock.patch.object(zoho_sync_main, "_output_dir", return_value=root), \
                    mock.patch.object(zoho_sync_main, "_db_store", return_value=MemoryStore()):
                run = zoho_sync_main.build_run(replay="oldrun")
            self.assertIsInstance(run.gateway, ReplayGateway)
            self.assertEqual(run.mode, "replay")

    def test_build_run_live_stamps_dubai_start_time(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            with mock.patch.object(zoho_sync_main, "_output_dir", return_value=root), \
                    mock.patch.object(zoho_sync_main, "_db_store", return_value=MemoryStore()), \
                    mock.patch("zoho_client.ZohoClient"):
                run = zoho_sync_main.build_run(yes_live=True)
            self.assertEqual(run.mode, "live")
            self.assertEqual(run.started_at.utcoffset(), timedelta(hours=4))

    def test_replay_writes_same_rows_without_network(self) -> None:
        list_row = {**_INVOICE_LIST_ROW, "last_modified_time": WM_LATER}
        detail = {**_INVOICE_DETAIL, "last_modified_time": WM_LATER}
        list_body = {"invoices": [list_row], "page_context": {"has_more_page": False}}
        detail_body = {"invoice": detail}

        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            store_live = MemoryStore()
            store_live.set_watermark("invoices", WM)
            _seed_sales_masters(store_live)
            client = _StubZohoClient()
            client.queue = [list_body, detail_body]
            budget = Budget(root / "stamp", interval=0)
            client._on_auth = budget.before_call
            runlog = RunLog(root, "captured")
            live_gw = LiveGateway(client, budget, runlog, sleep=lambda _s: None)
            run_live = Run(
                gateway=live_gw,
                store=store_live,
                cache=Cache(root / "cache"),
                runlog=runlog,
                run_id="captured",
                mode="live",
            )
            live_stats = pipeline.sync_dataset(run_live, INVOICES)
            self.assertTrue(live_stats["list_complete"])
            live_invoice = dict(store_live.get("sales_invoices", "INV1") or {})
            live_line = dict(store_live.get("sales_lines", "LI1") or {})
            self.assertTrue(live_invoice)
            self.assertTrue(live_line)

            store_replay = MemoryStore()
            store_replay.set_watermark("invoices", WM)
            _seed_sales_masters(store_replay)
            replay_gw = ReplayGateway(root / "runs" / "captured")
            run_replay = Run(
                gateway=replay_gw,
                store=store_replay,
                cache=Cache(root / "cache"),
                runlog=RunLog(root, "replayed"),
                run_id="replayed",
                mode="replay",
            )
            replay_stats = pipeline.sync_dataset(run_replay, INVOICES)
            self.assertTrue(replay_stats["list_complete"])
            replay_invoice = dict(store_replay.get("sales_invoices", "INV1") or {})
            replay_line = dict(store_replay.get("sales_lines", "LI1") or {})
            for key in ("invoice_id", "customer_id", "status", "net_sales"):
                self.assertEqual(replay_invoice.get(key), live_invoice.get(key), key)
            for key in ("line_item_id", "item_id", "net_sales"):
                self.assertEqual(replay_line.get(key), live_line.get(key), key)
            self.assertEqual(client.calls[0][0], "/invoices")  # only the live stub was used

    def test_replay_into_empty_database_serves_masters_from_cache(self) -> None:
        list_row = {**_INVOICE_LIST_ROW, "last_modified_time": WM_LATER}
        detail = {**_INVOICE_DETAIL, "last_modified_time": WM_LATER}
        list_body = {"invoices": [list_row], "page_context": {"has_more_page": False}}

        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache = Cache(root / "cache")
            cache.write("invoices", "INV1", detail)
            cache.write("contacts", "C1", _contact("C1", "customer"))
            cache.write("items", "IT1", {"item_id": "IT1", "name": "Item", "purchase_rate": 20})
            cache.write("salespersons", "SP1", {"salesperson_id": "SP1", "salesperson_name": "Sam"})

            runlog = RunLog(root, "captured")
            runlog.save_page("invoices", "/invoices", {"last_modified_time": WM, "page": 1, "per_page": PER_PAGE}, list_body)
            runlog.save_page("locations", "/locations", None, {"locations": [{"location_id": "L1", "location_name": "HQ"}]})

            store_replay = MemoryStore()
            store_replay.set_watermark("invoices", WM)
            replay_gw = ReplayGateway(root / "runs" / "captured")
            run_replay = Run(
                gateway=replay_gw,
                store=store_replay,
                cache=cache,
                runlog=RunLog(root, "replayed"),
                run_id="replayed",
                mode="replay",
            )
            replay_stats = pipeline.sync_dataset(run_replay, INVOICES)
            self.assertTrue(replay_stats["list_complete"])
            self.assertTrue(store_replay.has("sales_invoices", "INV1"))
            self.assertTrue(store_replay.has("customers", "C1"))
            self.assertTrue(store_replay.has("items", "IT1"))


class PipelineTests(unittest.TestCase):
    """Remaining FakeGateway / MemoryStore pipeline cases (task 10)."""

    def test_list_sends_raw_watermark_and_bill_equal_timestamp_is_noop(self) -> None:
        store = MemoryStore()
        store.set_watermark("bills", WM)
        _seed_vendor_masters(store)
        existing = BILLS.header_from_list({
            "bill_id": "B1", "bill_number": "BILL-1", "vendor_id": "V1", "vendor_name": "Vendor",
            "status": "open", "date": "2026-10-01", "total": "50", "last_modified_time": WM,
        })
        store.upsert("purchase_docs", [existing])
        store.replace_lines("purchase_lines", "doc_id", "B1", [{
            "line_item_id": "BL1", "kind": "bill", "doc_id": "B1", "item_id": "IT1",
            "quantity": Decimal("1"), "rate": Decimal("45"), "amount": Decimal("45"),
        }])
        list_row = {
            "bill_id": "B1", "bill_number": "BILL-1", "vendor_id": "V1", "vendor_name": "Vendor",
            "status": "open", "date": "2026-10-01", "total": "50", "last_modified_time": WM,
        }
        detail = {
            "bill_id": "B1", "vendor_id": "V1", "date": "2026-10-01",
            "sub_total": "45", "discount_total": "0", "tax_total": "5", "total": "50",
            "line_items": [{
                "line_item_id": "BL1", "item_id": "IT1", "quantity": "1",
                "rate": "45", "item_total": "45",
            }],
            "last_modified_time": WM,
        }
        gw = FakeGateway()
        gw.add("/bills", _list_params(), {"bills": [list_row], "page_context": {"has_more_page": False}})
        gw.add("/bills/B1", None, {"bill": detail})
        with TemporaryDirectory() as tmp:
            run = _test_run(gw, store=store, cache_root=Path(tmp))
            stats = pipeline.sync_dataset(run, BILLS)
        self.assertEqual(gw.calls[0], ("/bills", _list_params()))
        self.assertEqual(stats["watermark_before"], WM)
        self.assertEqual(stats["watermark_after"], WM)
        self.assertEqual(store.get("purchase_docs", ("bill", "B1"))["doc_id"], "B1")
        self.assertEqual(store.get("purchase_lines", "BL1")["doc_id"], "B1")

    def test_max_calls_leaves_watermark_finished_list_moves_with_pending(self) -> None:
        store = MemoryStore()
        store.set_watermark("invoices", WM)
        _seed_sales_masters(store)
        row_ok = {**_INVOICE_LIST_ROW, "invoice_id": "INV1", "last_modified_time": WM_LATER}
        row_bad = {
            **_INVOICE_LIST_ROW, "invoice_id": "INV2", "customer_id": "",
            "last_modified_time": "2026-10-03T09:00:00+0400",
        }
        gw_finish = FakeGateway()
        gw_finish.add("/invoices", _list_params(), {
            "invoices": [row_ok, row_bad], "page_context": {"has_more_page": False},
        })
        gw_finish.add("/invoices/INV1", None, {"invoice": {**_INVOICE_DETAIL, "invoice_id": "INV1"}})
        with TemporaryDirectory() as tmp:
            run = _test_run(gw_finish, store=store, cache_root=Path(tmp))
            stats = pipeline.sync_dataset(run, INVOICES)
        self.assertTrue(stats["list_complete"])
        self.assertEqual(stats["watermark_after"], "2026-10-03T09:00:00+0400")
        self.assertTrue(store.has("sales_invoices", "INV1"))
        self.assertFalse(store.has("sales_invoices", "INV2"))
        self.assertEqual(len(store.list_pending("invoices")), 1)

        store2 = MemoryStore()
        store2.set_watermark("invoices", WM)
        _seed_sales_masters(store2)
        gw_stop = FakeGateway()
        gw_stop.add("/invoices", _list_params(page=1), {
            "invoices": [row_ok], "page_context": {"has_more_page": True},
        })
        gw_stop.add("/invoices/INV1", None, {"invoice": {**_INVOICE_DETAIL, "invoice_id": "INV1"}})
        gw_stop.add("/invoices", _list_params(page=2), BudgetExceeded("max_calls"))
        with TemporaryDirectory() as tmp:
            run2 = _test_run(gw_stop, store=store2, cache_root=Path(tmp))
            stats2 = pipeline.sync_dataset(run2, INVOICES)
        self.assertFalse(stats2["list_complete"])
        self.assertEqual(stats2["watermark_after"], WM)
        self.assertEqual(stats2.get("stopped"), "max_calls")

    def test_no_watermark_refuses_and_lists_nothing(self) -> None:
        gw = FakeGateway()
        run = _test_run(gw)
        stats = pipeline.sync_dataset(run, INVOICES)
        self.assertEqual(stats.get("refused"), "no_watermark")
        self.assertEqual(gw.calls, [])

    def test_debit_note_id_never_lands_in_sales_invoices(self) -> None:
        store = MemoryStore()
        store.set_watermark("debit_notes", WM)
        store.set_watermark("invoices", WM)
        _seed_sales_masters(store)
        dn_list = {
            **_INVOICE_LIST_ROW, "invoice_id": "DN1", "invoice_number": "DN-1",
            "type": "debit_note", "last_modified_time": WM_LATER,
        }
        dn_detail = {
            **_INVOICE_DETAIL, "invoice_id": "DN1", "invoice_number": "DN-1",
            "type": "debit_note", "last_modified_time": WM_LATER,
        }
        gw = FakeGateway()
        gw.add("/invoices", _list_params(filter_by="Type.DebitNote"), {
            "invoices": [dn_list], "page_context": {"has_more_page": False},
        })
        gw.add("/invoices/DN1", None, {"invoice": dn_detail})
        # Invoice pass also returns the same id with type debit_note (reroute path).
        gw.add("/invoices", _list_params(), {
            "invoices": [dn_list], "page_context": {"has_more_page": False},
        })
        with TemporaryDirectory() as tmp:
            run = _test_run(gw, store=store, cache_root=Path(tmp))
            pipeline.sync_dataset(run, DEBIT_NOTES)
            pipeline.sync_dataset(run, INVOICES)
        self.assertTrue(store.has("debit_notes", "DN1"))
        self.assertFalse(store.has("sales_invoices", "DN1"))
        self.assertTrue(store.has("debit_note_lines", "LI1"))

    def test_missing_master_is_ensured_before_insert(self) -> None:
        store = MemoryStore()
        store.set_watermark("invoices", WM)
        # Item/salesperson/location pre-seeded; customer must be ensured from Zoho.
        store.upsert("items", [{"item_id": "IT1", "name": "Item", "purchase_rate": Decimal("20")}])
        store.upsert("salespersons", [{"salesperson_id": "SP1", "salesperson_name": "Sam"}])
        store.upsert("locations", [{"location_id": "L1", "location_name": "HQ"}])
        list_row = {**_INVOICE_LIST_ROW, "last_modified_time": WM_LATER}
        detail = {**_INVOICE_DETAIL, "last_modified_time": WM_LATER}
        gw = FakeGateway()
        gw.add("/invoices", _list_params(), {"invoices": [list_row], "page_context": {"has_more_page": False}})
        gw.add("/invoices/INV1", None, {"invoice": detail})
        gw.add("/contacts/C1", None, {"contact": _contact("C1", "customer")})
        with TemporaryDirectory() as tmp:
            run = _test_run(gw, store=store, cache_root=Path(tmp))
            pipeline.sync_dataset(run, INVOICES)
        self.assertTrue(store.has("customers", "C1"))
        self.assertEqual(store.get("sales_invoices", "INV1")["customer_id"], "C1")
        self.assertIn(("/contacts/C1", None), gw.calls)

    def test_blank_optional_null_blank_party_stores_nothing(self) -> None:
        store = MemoryStore()
        store.set_watermark("invoices", WM)
        _seed_sales_masters(store)
        ok = {
            **_INVOICE_LIST_ROW, "invoice_id": "INV1", "salesperson_id": "", "location_id": "",
            "last_modified_time": WM_LATER,
        }
        blank_party = {
            **_INVOICE_LIST_ROW, "invoice_id": "INV2", "customer_id": "",
            "last_modified_time": "2026-10-03T09:00:00+0400",
        }
        detail_ok = {
            **_INVOICE_DETAIL, "invoice_id": "INV1", "salesperson_id": "", "location_id": "",
            "last_modified_time": WM_LATER,
        }
        gw = FakeGateway()
        gw.add("/invoices", _list_params(), {
            "invoices": [ok, blank_party], "page_context": {"has_more_page": False},
        })
        gw.add("/invoices/INV1", None, {"invoice": detail_ok})
        with TemporaryDirectory() as tmp:
            run = _test_run(gw, store=store, cache_root=Path(tmp))
            stats = pipeline.sync_dataset(run, INVOICES)
        inv = store.get("sales_invoices", "INV1")
        self.assertIsNotNone(inv)
        self.assertIsNone(inv["salesperson_id"])
        self.assertIsNone(inv["location_id"])
        self.assertFalse(store.has("sales_invoices", "INV2"))
        self.assertEqual(stats["pending"], 1)

    def test_master_404_pends_and_needs_attention_on_third_attempt(self) -> None:
        store = MemoryStore()
        store.set_watermark("invoices", WM)
        list_row = {**_INVOICE_LIST_ROW, "last_modified_time": WM_LATER}
        gw = FakeGateway()
        gw.add("/invoices", _list_params(), {"invoices": [list_row], "page_context": {"has_more_page": False}})
        gw.add("/contacts/C1", None, NotFound("missing customer"))
        summary: dict = {"needs_attention": []}
        with TemporaryDirectory() as tmp:
            run = _test_run(gw, store=store, cache_root=Path(tmp))
            pipeline.sync_dataset(run, INVOICES, summary=summary)
            self.assertFalse(store.has("sales_invoices", "INV1"))
            self.assertEqual(store.list_pending("invoices")[0]["attempts"], 1)
            # Later runs: list empty, pending retried.
            gw.add("/invoices", {
                "last_modified_time": WM_LATER, "page": 1, "per_page": PER_PAGE,
            }, {"invoices": [], "page_context": {"has_more_page": False}})
            pipeline.sync_dataset(run, INVOICES, summary=summary)
            self.assertEqual(store.list_pending("invoices")[0]["attempts"], 2)
            self.assertEqual(summary["needs_attention"], [])
            pipeline.sync_dataset(run, INVOICES, summary=summary)
        self.assertEqual(store.list_pending("invoices")[0]["attempts"], 3)
        self.assertFalse(store.has("sales_invoices", "INV1"))
        self.assertEqual(summary["needs_attention"][0]["doc_id"], "INV1")
        self.assertEqual(summary["needs_attention"][0]["attempts"], 3)

    def test_debit_note_loads_reference_invoice_first(self) -> None:
        store = MemoryStore()
        store.set_watermark("debit_notes", WM)
        _seed_sales_masters(store)
        dn_list = {
            **_INVOICE_LIST_ROW, "invoice_id": "DN1", "invoice_number": "DN-1",
            "type": "debit_note", "last_modified_time": WM_LATER,
        }
        dn_detail = {
            **_INVOICE_DETAIL, "invoice_id": "DN1", "invoice_number": "DN-1",
            "type": "debit_note", "reference_invoice_id": "INV9",
            "last_modified_time": WM_LATER,
        }
        inv_detail = {**_INVOICE_DETAIL, "invoice_id": "INV9", "invoice_number": "INV-009"}
        gw = FakeGateway()
        gw.add("/invoices", _list_params(filter_by="Type.DebitNote"), {
            "invoices": [dn_list], "page_context": {"has_more_page": False},
        })
        gw.add("/invoices/DN1", None, {"invoice": dn_detail})
        gw.add("/invoices/INV9", None, {"invoice": inv_detail})
        with TemporaryDirectory() as tmp:
            run = _test_run(gw, store=store, cache_root=Path(tmp))
            pipeline.sync_dataset(run, DEBIT_NOTES)
        self.assertTrue(store.has("sales_invoices", "INV9"))
        self.assertTrue(store.has("debit_notes", "DN1"))
        self.assertEqual(store.get("debit_notes", "DN1")["reference_invoice_id"], "INV9")
        # DN detail is loaded first (discovers the ref); reference invoice follows.
        paths = [c[0] for c in gw.calls]
        self.assertEqual(paths.count("/invoices/DN1"), 1)
        self.assertIn("/invoices/INV9", paths)
        self.assertLess(paths.index("/invoices/DN1"), paths.index("/invoices/INV9"))

    def test_missing_lines_from_new_detail_are_deleted(self) -> None:
        store = MemoryStore()
        store.set_watermark("invoices", WM)
        _seed_sales_masters(store)
        store.upsert("sales_invoices", [{"invoice_id": "INV1", "customer_id": "C1", "status": "closed"}])
        store.replace_lines("sales_lines", "invoice_id", "INV1", [
            {"line_item_id": "LI1", "invoice_id": "INV1", "item_id": "IT1", "net_sales": Decimal("10")},
            {"line_item_id": "LI2", "invoice_id": "INV1", "item_id": "IT1", "net_sales": Decimal("20")},
        ])
        list_row = {**_INVOICE_LIST_ROW, "last_modified_time": WM_LATER}
        detail = {
            **_INVOICE_DETAIL, "last_modified_time": WM_LATER,
            "line_items": [{
                "line_item_id": "LI1", "item_id": "IT1", "quantity": "2", "rate": "50",
                "item_total": "100", "purchase_price": "20", "unit": "pcs", "base_unit": "pcs",
            }],
        }
        gw = FakeGateway()
        gw.add("/invoices", _list_params(), {"invoices": [list_row], "page_context": {"has_more_page": False}})
        gw.add("/invoices/INV1", None, {"invoice": detail})
        with TemporaryDirectory() as tmp:
            run = _test_run(gw, store=store, cache_root=Path(tmp))
            pipeline.sync_dataset(run, INVOICES)
        self.assertTrue(store.has("sales_lines", "LI1"))
        self.assertFalse(store.has("sales_lines", "LI2"))

    def test_vendor_payment_children_require_bill_on_purchase_docs(self) -> None:
        store = MemoryStore()
        store.set_watermark("vendor_payments", WM)
        _seed_vendor_masters(store)
        list_row = {
            "payment_id": "P1", "payment_number": "VP-1", "vendor_id": "V1",
            "vendor_name": "Vendor", "date": "2026-10-01", "last_modified_time": WM_LATER,
        }
        detail = {
            "payment_id": "P1", "vendor_id": "V1", "date": "2026-10-01",
            "paid_through_account_id": "A1", "last_modified_time": WM_LATER,
            "bills": [{
                "bill_payment_id": "BP1", "bill_id": "B9",
                "amount_applied": "50", "tax_amount_withheld": "0",
            }],
        }
        bill_detail = {
            "bill_id": "B9", "vendor_id": "V1", "date": "2026-10-01",
            "sub_total": "50", "discount_total": "0", "tax_total": "0",
            "line_items": [{
                "line_item_id": "BL9", "item_id": "IT1", "quantity": "1",
                "rate": "50", "item_total": "50",
            }],
        }
        gw = FakeGateway()
        gw.add("/vendorpayments", _list_params(), {
            "vendorpayments": [list_row], "page_context": {"has_more_page": False},
        })
        gw.add("/vendorpayments/P1", None, {"vendorpayment": detail})
        gw.add("/bills/B9", None, {"bill": bill_detail})
        with TemporaryDirectory() as tmp:
            run = _test_run(gw, store=store, cache_root=Path(tmp))
            pipeline.sync_dataset(run, VENDOR_PAYMENTS)
        self.assertTrue(store.has("purchase_docs", ("bill", "B9")))
        self.assertTrue(store.has("vendor_payments", "P1"))
        child = store.get("vendor_payment_bills", "BP1")
        self.assertEqual(child["bill_id"], "B9")
        self.assertEqual(child["payment_id"], "P1")
        # Payment detail loads first; bill ref is fetched before children are written.
        paths = [c[0] for c in gw.calls]
        self.assertIn("/bills/B9", paths)
        self.assertIn("/vendorpayments/P1", paths)
        self.assertLess(paths.index("/vendorpayments/P1"), paths.index("/bills/B9"))

    def test_line_item_404_stores_no_header_and_pends(self) -> None:
        store = MemoryStore()
        store.set_watermark("invoices", WM)
        store.upsert("customers", [{"customer_id": "C1", "contact_name": "Acme"}])
        store.upsert("salespersons", [{"salesperson_id": "SP1", "salesperson_name": "Sam"}])
        store.upsert("locations", [{"location_id": "L1", "location_name": "HQ"}])
        list_row = {**_INVOICE_LIST_ROW, "invoice_id": "INV1", "last_modified_time": WM_LATER}
        detail = {
            **_INVOICE_DETAIL, "invoice_id": "INV1", "last_modified_time": WM_LATER,
            "line_items": [{
                "line_item_id": "LI1", "item_id": "IT_MISSING", "quantity": "1", "rate": "10", "item_total": "10",
            }],
        }
        gw = FakeGateway()
        gw.add("/invoices", _list_params(), {"invoices": [list_row], "page_context": {"has_more_page": False}})
        gw.add("/invoices/INV1", None, {"invoice": detail})
        gw.add("/items/IT_MISSING", None, NotFound("item gone"))
        with TemporaryDirectory() as tmp:
            run = _test_run(gw, store=store, cache_root=Path(tmp))
            stats = pipeline.sync_dataset(run, INVOICES)
        self.assertFalse(store.has("sales_invoices", "INV1"))
        self.assertEqual(store.iter_table("sales_lines"), [])
        self.assertEqual(stats["pending"], 1)
        self.assertEqual(len(store.list_pending("invoices")), 1)

    def test_debit_note_reference_invoice_failure_stores_nothing(self) -> None:
        store = MemoryStore()
        store.set_watermark("debit_notes", WM)
        _seed_sales_masters(store)
        dn_list = {
            **_INVOICE_LIST_ROW, "invoice_id": "DN1", "invoice_number": "DN-1",
            "type": "debit_note", "last_modified_time": WM_LATER,
        }
        dn_detail = {
            **_INVOICE_DETAIL, "invoice_id": "DN1", "invoice_number": "DN-1",
            "type": "debit_note", "reference_invoice_id": "INV_FAIL",
            "last_modified_time": WM_LATER,
        }
        gw = FakeGateway()
        gw.add("/invoices", _list_params(filter_by="Type.DebitNote"), {
            "invoices": [dn_list], "page_context": {"has_more_page": False},
        })
        gw.add("/invoices/DN1", None, {"invoice": dn_detail})
        gw.add("/invoices/INV_FAIL", None, NotFound("invoice not found"))
        with TemporaryDirectory() as tmp:
            run = _test_run(gw, store=store, cache_root=Path(tmp))
            stats = pipeline.sync_dataset(run, DEBIT_NOTES)
        self.assertFalse(store.has("debit_notes", "DN1"))
        self.assertEqual(store.iter_table("debit_note_lines"), [])
        self.assertEqual(stats["pending"], 1)
        self.assertEqual(len(store.list_pending("debit_notes")), 1)

    def test_retry_preserves_list_only_fields(self) -> None:
        store = MemoryStore()
        store.set_watermark("invoices", WM)
        _seed_sales_masters(store)
        store.upsert("sales_invoices", [{
            "invoice_id": "INV1",
            "customer_id": "C1",
            "status": "closed",
            "balance": Decimal("50.00"),
            "salesperson_name": "Sam",
            "date": date(2026, 10, 1),
            "total": Decimal("100.00"),
        }])
        detail = {
            "invoice_id": "INV1", "customer_id": "C1", "date": "2026-10-01",
            "sub_total": "100", "discount_total": "0", "tax_total": "0",
            "line_items": [{
                "line_item_id": "LI1", "item_id": "IT1", "quantity": "2",
                "rate": "50", "item_total": "100",
            }],
            "last_modified_time": WM_LATER,
        }
        store.add_pending("invoices", "INV1", modified_time=WM_LATER, reason="retry_test")
        gw = FakeGateway()
        gw.add("/invoices", _list_params(), {"invoices": [], "page_context": {"has_more_page": False}})
        gw.add("/invoices/INV1", None, {"invoice": detail})
        with TemporaryDirectory() as tmp:
            run = _test_run(gw, store=store, cache_root=Path(tmp))
            pipeline.sync_dataset(run, INVOICES)
        inv = store.get("sales_invoices", "INV1")
        self.assertIsNotNone(inv)
        self.assertEqual(inv["balance"], Decimal("50.00"))
        self.assertEqual(inv["salesperson_name"], "Sam")
        self.assertEqual(inv["net_sales"], Decimal("100.00"))
        self.assertEqual(len(store.list_pending("invoices")), 0)

    def test_http_failure_on_one_dataset_does_not_stop_run_and_leaves_watermark(self) -> None:
        store = MemoryStore()
        store.set_watermark("debit_notes", WM)
        store.set_watermark("invoices", WM)
        store.set_watermark("bills", WM)
        _seed_sales_masters(store)
        _seed_vendor_masters(store)

        gw = FakeGateway()
        gw.add("/invoices", _list_params(filter_by="Type.DebitNote"), {
            "invoices": [{**_INVOICE_LIST_ROW, "invoice_id": "DN1", "last_modified_time": WM_LATER, "type": "debit_note"}],
            "page_context": {"has_more_page": False},
        })
        gw.add("/invoices/DN1", None, {"invoice": {**_INVOICE_DETAIL, "invoice_id": "DN1", "type": "debit_note"}})

        gw.add("/invoices", _list_params(), ZohoHTTPError("Zoho list 500 server error", status=500))

        gw.add("/bills", _list_params(), {"bills": [], "page_context": {"has_more_page": False}})

        with TemporaryDirectory() as tmp:
            run = _test_run(gw, store=store, cache_root=Path(tmp))
            summary = pipeline.run_all(run, specs=(DEBIT_NOTES, INVOICES, BILLS))

        self.assertEqual(store.get_watermark("debit_notes"), WM_LATER)
        self.assertEqual(summary["datasets"]["debit_notes"]["watermark_after"], WM_LATER)

        self.assertEqual(store.get_watermark("invoices"), WM)
        self.assertEqual(summary["datasets"]["invoices"]["watermark_after"], WM)
        self.assertIn("error", summary["datasets"]["invoices"])

        self.assertIn("bills", summary["datasets"])
        self.assertTrue(summary["datasets"]["bills"]["list_complete"])


import os


@unittest.skipUnless(os.getenv("RUN_DB_TESTS"), "opt-in MariaDB test: set RUN_DB_TESTS=1")
class DbStoreMariaDbIntegrationTests(unittest.TestCase):
    """Opt-in integration test on real MariaDB 10.11 in STRICT_TRANS_TABLES mode."""

    def setUp(self) -> None:
        from seed_common import connect
        self.conn = connect("mysql")
        with self.conn.cursor() as cur:
            cur.execute("SET SESSION sql_mode = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION'")
            cur.execute("CREATE DATABASE IF NOT EXISTS `mis_throwaway_test`")
        self.conn.select_db("mis_throwaway_test")
        with self.conn.cursor() as cur:
            cur.execute("SET SESSION sql_mode = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION'")
            cur.execute("""
                CREATE TABLE IF NOT EXISTS `sales_invoices` (
                    `invoice_id` VARCHAR(40) NOT NULL,
                    `customer_id` VARCHAR(40) NULL,
                    `date` DATE NOT NULL,
                    `total` DECIMAL(18,2) NOT NULL DEFAULT 0.00,
                    `net_sales` DECIMAL(18,2) NOT NULL DEFAULT 0.00,
                    `cogs` DECIMAL(18,2) NOT NULL DEFAULT 0.00,
                    `cogs_synced_at` DATETIME NULL,
                    PRIMARY KEY (`invoice_id`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS `sales_lines` (
                    `line_item_id` VARCHAR(40) NOT NULL,
                    `invoice_id` VARCHAR(40) NOT NULL,
                    `date` DATE NOT NULL,
                    `quantity` DECIMAL(18,4) NOT NULL DEFAULT 0.0000,
                    `purchase_price` DECIMAL(18,4) NOT NULL DEFAULT 0.0000,
                    `conversion_rate` DECIMAL(18,6) NOT NULL DEFAULT 1.000000,
                    `cogs` DECIMAL(18,2) NOT NULL DEFAULT 0.00,
                    PRIMARY KEY (`line_item_id`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS `gl_journals` (
                    `account_id` VARCHAR(40) NOT NULL,
                    `categorized_transaction_id` VARCHAR(40) NOT NULL,
                    `transaction_id` VARCHAR(40) NOT NULL,
                    `transaction_type` VARCHAR(50) NOT NULL,
                    `transaction_date` DATE NOT NULL,
                    `amount` DECIMAL(18,2) NOT NULL DEFAULT 0.00,
                    PRIMARY KEY (`account_id`, `categorized_transaction_id`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)
        self.conn.commit()
        self.store = DbStore(self.conn)

    def tearDown(self) -> None:
        try:
            with self.conn.cursor() as cur:
                cur.execute("DROP DATABASE IF EXISTS `mis_throwaway_test`")
            self.conn.commit()
            self.conn.close()
        except Exception:
            pass

    def test_strict_mode_upsert_update_replace_lines_and_keyed_reads(self) -> None:
        # 1. Upsert full row on table with NOT NULL column without default (date)
        self.store.upsert("sales_invoices", [{
            "invoice_id": "INV1", "customer_id": "C1", "date": date(2026, 10, 1),
            "total": Decimal("100.00"), "net_sales": Decimal("100.00"),
        }])
        self.assertTrue(self.store.has("sales_invoices", "INV1"))

        # 2. Update partial row (setting cogs/cogs_synced_at) omitting NOT NULL date - must succeed under strict mode!
        now = datetime(2026, 10, 21, 2, 0, 0)
        self.store.update("sales_invoices", "INV1", {"cogs": Decimal("40.00"), "cogs_synced_at": now})
        inv = self.store.get("sales_invoices", "INV1")
        self.assertEqual(inv["cogs"], Decimal("40.00"))
        self.assertEqual(inv["cogs_synced_at"], now)
        self.assertEqual(inv["date"], date(2026, 10, 1))

        # 2b. Rewriting the same values still finds the row (rowcount is changed-rows, not matched-rows).
        self.store.update("sales_invoices", "INV1", {"cogs": Decimal("40.00"), "cogs_synced_at": now})

        # 3. replace_lines
        self.store.replace_lines("sales_lines", "invoice_id", "INV1", [
            {"line_item_id": "L1", "invoice_id": "INV1", "date": date(2026, 10, 1), "quantity": Decimal("2"), "purchase_price": Decimal("10")},
            {"line_item_id": "L2", "invoice_id": "INV1", "date": date(2026, 10, 1), "quantity": Decimal("1"), "purchase_price": Decimal("20")},
        ])
        lines = self.store.iter_where("sales_lines", where_in={"invoice_id": ["INV1"]})
        self.assertEqual(len(lines), 2)

        # 4. replace_range on gl_journals
        self.store.replace_range("A1", date(2026, 10, 1), date(2026, 10, 1), [
            {"account_id": "A1", "categorized_transaction_id": "CT1", "transaction_id": "INV1",
             "transaction_type": "inventory_valuation_for_invoice", "transaction_date": date(2026, 10, 1), "amount": Decimal("40.00")},
        ])
        journals = self.store.iter_where("gl_journals", where={"account_id": "A1"})
        self.assertEqual(len(journals), 1)
        self.assertEqual(journals[0]["amount"], Decimal("40.00"))


if __name__ == "__main__":
    unittest.main()
