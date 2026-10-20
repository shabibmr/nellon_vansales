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
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path
from tempfile import TemporaryDirectory

from zoho_client import ZohoHTTPError
from zoho_sync import cogs, pipeline, postings
from zoho_sync.budget import Budget, BudgetExceeded
from zoho_sync.cache import Cache
from zoho_sync.context import Run
from zoho_sync.gateway import FakeGateway, LiveGateway, NotFound, PageNotFound, ReplayGateway
from zoho_sync.masters import WrongType, ensure
from zoho_sync.ranges import (
    DateRange,
    cost_of_sales_ranges,
    format_range_doc_id,
    merge_ranges,
    parse_pending_doc_id,
    trailing_window,
)
from zoho_sync.runlog import RunLog, cleanup_old_runs, new_run_id
from zoho_sync.specs import ALL_SPECS, BILLS, DEBIT_NOTES, INVOICES, VENDOR_PAYMENTS
from zoho_sync.store import MemoryStore
from zoho_sync.store_db import DbStore, UnknownColumn
from zoho_sync.watermark import NoWatermark, encode_watermark, get_watermark, seed, set_watermark

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


class WatermarkTests(unittest.TestCase):
    def test_round_trip(self) -> None:
        store = MemoryStore()
        set_watermark(store, "invoices", "2026-10-21T14:02:51+0400")
        self.assertEqual(get_watermark(store, "invoices"), "2026-10-21T14:02:51+0400")

    def test_missing_watermark_raises(self) -> None:
        store = MemoryStore()
        with self.assertRaises(NoWatermark):
            get_watermark(store, "invoices")

    def test_percent_encodes_plus_only(self) -> None:
        self.assertEqual(encode_watermark("2026-10-21T14:02:51+0400"), "2026-10-21T14:02:51%2B0400")
        self.assertEqual(encode_watermark("2026-10-21T14:02:51-0400"), "2026-10-21T14:02:51-0400")

    def test_seed_from_header_tables(self) -> None:
        store = MemoryStore()
        store.upsert("sales_invoices", [{"invoice_id": "I1", "last_modified_time": "2026-10-20T00:00:00+0400"}])
        store.upsert("sales_invoices", [{"invoice_id": "I2", "last_modified_time": "2026-10-21T00:00:00+0400"}])
        result = seed(store, {"invoices": "sales_invoices", "bills": "purchase_docs"})
        self.assertEqual(result["invoices"], "2026-10-21T00:00:00+0400")
        self.assertIsNone(result["bills"])
        self.assertEqual(get_watermark(store, "invoices"), "2026-10-21T00:00:00+0400")
        with self.assertRaises(NoWatermark):
            get_watermark(store, "bills")


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


class StoreDbTests(unittest.TestCase):
    def test_rejects_mapper_key_that_is_not_a_column(self) -> None:
        store = DbStore(conn=None, columns={"customers": {"customer_id", "contact_name", "status"}})
        with self.assertRaises(UnknownColumn):
            store.upsert("customers", [{"customer_id": "C1", "contact_name": "Acme", "nope": "x"}])


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


class CostOfSalesPipelineTests(unittest.TestCase):
    """Task 7 wired into `pipeline.run_all` / `run_cost_of_sales` (plan, "Step 3
    — Cost of Sales pass"): runs once, after every dataset above has listed."""

    def test_run_all_skips_cost_of_sales_when_no_spec_has_cogs(self) -> None:
        store = MemoryStore()
        store.set_watermark("bills", "2020-01-01T00:00:00+0400")
        gw = FakeGateway()
        gw.add(
            "/bills",
            {"last_modified_time": "2020-01-01T00:00:00%2B0400", "page": 1, "per_page": 200},
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


if __name__ == "__main__":
    unittest.main()
