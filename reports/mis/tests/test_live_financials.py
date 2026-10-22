"""Live financials (reports/live_financials.py) against a fake Zoho GL — no network, no DB.

    .venv/bin/python -m unittest tests.test_live_financials
"""

from __future__ import annotations

import threading
import time
import unittest
from datetime import date, timedelta
from unittest import mock

from backend.reports import live_financials as live
from backend.reports import monthly_trial_balance as mtb
from common import periods
from common.periods import Col

START = date(2024, 1, 1)
FY_MONTH = 4  # fiscal year starts in April

ACCOUNTS = [  # id, type, pl_bs, category
    ("bank", "bank", "BS", "Cash and bank balances"),
    ("recv", "accounts_receivable", "BS", "Trade Receivables"),
    ("pay", "accounts_payable", "BS", "Trade payables"),
    ("cap", "equity", "BS", "Share Capital"),
    ("sales", "income", "PL", "Revenue Booked"),
    ("cogs", "cost_of_goods_sold", "PL", "COGS"),
    ("rent", "expense", "PL", "Office Expenses"),
]
SNAPSHOT = {
    "organization_name": "Test Co", "currency_code": "AED", "fiscal_year_start_month": FY_MONTH,
    "accounts": [{"account_id": a, "account_name": a.title(), "account_code": str(i), "account_type": t}
                 for i, (a, t, _, _) in enumerate(ACCOUNTS)],
}
OVERRIDES = {a: {"account_id": a, "pl_bs": p, "category": c, "sub_category": c} for a, _, p, c in ACCOUNTS}


def postings(d: date) -> list[tuple[str, float, float]]:
    """(account, debit, credit) for one day; every day balances."""
    out = [("recv", 100, 0), ("sales", 0, 100), ("cogs", 60, 0), ("pay", 0, 60)]
    if d.day == 1:
        out += [("rent", 500, 0), ("bank", 0, 500)]
    if d.day == 10:
        out += [("bank", 3000, 0), ("recv", 0, 3000)]
    if d == date(2024, 1, 2):
        out += [("bank", 10000, 0), ("cap", 0, 10000)]
    return out


def gl(a: date, b: date) -> mtb.Moves:
    out: dict[str, list[float]] = {}
    d = max(a, START)
    while d <= b:
        for acc, dr, cr in postings(d):
            t = out.setdefault(acc, [0.0, 0.0])
            t[0] += dr
            t[1] += cr
        d += timedelta(days=1)
    return {k: (v[0], v[1]) for k, v in out.items()}


def net(acc: str, a: date, b: date) -> float:
    dr, cr = gl(a, b).get(acc, (0.0, 0.0))
    return dr - cr


class FakeZoho:
    def __init__(self, delay: float = 0.0, fail: bool = False):
        self.calls: list[tuple[date, date]] = []
        self.delay = delay
        self.fail = fail

    def __call__(self, a: date, b: date) -> mtb.Moves:
        if self.fail:
            raise RuntimeError("HTTP 503")
        time.sleep(self.delay)
        self.calls.append((a, b))
        return gl(a, b)


class Clock:
    def __init__(self) -> None:
        self.t = 1_000_000.0

    def __call__(self) -> float:
        return self.t


def cache(zoho: FakeZoho, clock: Clock | None = None) -> live.GLCache:
    return live.GLCache(zoho, ttl=900, clock=clock or Clock(), log=lambda s: None)


def weeks(a: date, b: date) -> list[Col]:
    out, s = [], a
    while s <= b:
        e = min(b, s + timedelta(days=6 - s.weekday()))
        out.append(Col(f"w{s}", s, e))
        s = e + timedelta(days=1)
    return out


def line(stmt: dict, label: str) -> dict:
    return next(ln["values"] for ln in stmt["lines"] if ln["label"] == label)


class SegmentsTest(unittest.TestCase):
    def test_cut_at_columns_and_fiscal_years(self):
        segs = mtb.segments([(date(2025, 2, 10), date(2025, 2, 28)), (date(2025, 3, 1), date(2025, 5, 31))], FY_MONTH)
        self.assertEqual(segs, [
            (date(2024, 4, 1), date(2025, 2, 9)),    # fiscal year start → first column (opening part)
            (date(2025, 2, 10), date(2025, 2, 28)),
            (date(2025, 3, 1), date(2025, 3, 31)),   # cut at the new fiscal year
            (date(2025, 4, 1), date(2025, 5, 31)),
        ])

    def test_total_column_adds_no_segment(self):
        cols = periods.month_cols(date(2025, 4, 1), date(2025, 6, 30))
        self.assertEqual(len(mtb.segments([(c.start, c.end) for c in cols], FY_MONTH)), 3)


class LiveTest(unittest.TestCase):
    def setUp(self):
        self.zoho = FakeZoho()
        self.clock = Clock()
        self.cache = cache(self.zoho, self.clock)

    def stmt(self, name, cols, **kw):
        return live.statement(name, cols, SNAPSHOT, OVERRIDES, cache=self.cache, **kw)

    def test_weekly_pl_matches_the_ledger_and_total(self):
        a, b = date(2025, 10, 1), date(2025, 10, 15)
        cols = weeks(a, b) + [Col("Total", a, b)]
        pl = self.stmt("PL", cols)
        self.assertEqual(pl["columns"], [c.key for c in cols])
        revenue = line(pl, "Total Revenue")
        for c in cols:
            self.assertAlmostEqual(revenue[c.key], -net("sales", c.start, c.end), places=2)
        self.assertAlmostEqual(sum(revenue[c.key] for c in cols[:-1]), revenue["Total"], places=2)
        net_profit = line(pl, "Net Profit")
        want = -(net("sales", a, b) + net("cogs", a, b) + net("rent", a, b))
        self.assertAlmostEqual(net_profit["Total"], want, places=2)
        self.assertEqual(pl["zoho_calls"], 1 + len(cols) - 1 + 1)  # opening + fiscal-year-to-start + weeks

    def test_balance_sheet_balances_across_a_fiscal_year_end(self):
        cols = [Col(f"q{i}", s, e) for i, (s, e) in enumerate([
            (date(2025, 1, 1), date(2025, 3, 31)), (date(2025, 4, 1), date(2025, 6, 30)),
            (date(2025, 7, 1), date(2025, 7, 17))])]
        bs = self.stmt("BS", cols)
        assets, cap_liab = line(bs, "Total Assets"), line(bs, "Total Capital & Liabilities")
        for c in cols:
            self.assertAlmostEqual(assets[c.key], cap_liab[c.key], places=2)
            self.assertAlmostEqual(line(bs, "Cash and bank balances")[c.key], net("bank", START, c.end), places=2)
        # Current-year earnings restart on 1 Apr; earlier years move to retained earnings.
        cye = line(bs, "Current Year Earnings")
        pl_net = lambda a, b: -(net("sales", a, b) + net("cogs", a, b) + net("rent", a, b))  # noqa: E731
        self.assertAlmostEqual(cye["q0"], pl_net(date(2024, 4, 1), date(2025, 3, 31)), places=2)
        self.assertAlmostEqual(cye["q1"], pl_net(date(2025, 4, 1), date(2025, 6, 30)), places=2)
        reserves = line(bs, "Reserves and surplus")
        self.assertAlmostEqual(reserves["q1"], pl_net(START, date(2025, 3, 31)), places=2)

    def test_trial_balance_opening_and_closing_net_to_zero(self):
        cols = [Col("2025-04", date(2025, 4, 10), date(2025, 4, 30)), Col("2025-05", date(2025, 5, 1), date(2025, 5, 31))]
        tb = live.trial_balance(cols, SNAPSHOT, OVERRIDES, cache=self.cache)
        self.assertAlmostEqual(sum(r["opening"] for r in tb["rows"]), 0, places=2)
        self.assertAlmostEqual(sum(r["closing"] for r in tb["rows"]), 0, places=2)
        sales = next(r for r in tb["rows"] if r["account_id"] == "sales")
        self.assertAlmostEqual(sales["opening"], net("sales", date(2025, 4, 1), date(2025, 4, 9)), places=2)
        self.assertAlmostEqual(sales["2025-05"], net("sales", date(2025, 5, 1), date(2025, 5, 31)), places=2)
        self.assertEqual((tb["from"], tb["to"]), ("2025-04-10", "2025-05-31"))

    def test_category_override_applies_without_refetch(self):
        cols = periods.month_cols(date(2025, 4, 1), date(2025, 4, 30))
        self.stmt("PL", cols)
        moved = {**OVERRIDES, "rent": {**OVERRIDES["rent"], "category": "Direct Expenses"}}
        pl = live.statement("PL", cols, SNAPSHOT, moved, cache=self.cache)
        self.assertEqual(pl["zoho_calls"], 0)
        self.assertAlmostEqual(line(pl, "Contribution Margin (CM)")["Total"],
                               line(pl, "Gross Margin (GM)")["Total"] - net("rent", date(2025, 4, 1), date(2025, 4, 30)), places=2)


class CacheTest(unittest.TestCase):
    COLS = periods.month_cols(date(2025, 4, 1), date(2025, 5, 31))

    def setUp(self):
        self.zoho = FakeZoho()
        self.clock = Clock()
        self.cache = cache(self.zoho, self.clock)

    def view(self, **kw):
        return live.statement("Executive Summary", self.COLS, SNAPSHOT, OVERRIDES, cache=self.cache, **kw)

    def test_repeat_view_within_ttl_makes_no_call(self):
        first = self.view()
        self.assertEqual(first["zoho_calls"], 3)  # opening + Apr + May
        self.clock.t += 899
        self.assertEqual(self.view()["zoho_calls"], 0)
        self.clock.t += 2
        again = self.view()
        self.assertEqual(again["zoho_calls"], 3)
        self.assertFalse(again["stale"])

    def test_overlapping_view_reuses_months(self):
        self.view()
        may_jun = live.statement("PL", periods.month_cols(date(2025, 5, 1), date(2025, 6, 30)), SNAPSHOT, OVERRIDES,
                                 cache=self.cache)
        self.assertEqual(may_jun["zoho_calls"], 1)  # opening (to the fiscal year), Apr and May cached: only Jun

    def test_refresh_is_limited_to_once_a_minute(self):
        self.view()
        self.clock.t += 30
        self.assertEqual(self.view(refresh=True)["zoho_calls"], 0)
        self.clock.t += 31
        self.assertEqual(self.view(refresh=True)["zoho_calls"], 3)

    def test_stale_copy_when_zoho_fails(self):
        self.view()
        self.clock.t += 1000
        self.zoho.fail = True
        out = self.view()
        self.assertTrue(out["stale"])
        self.assertEqual(out["zoho_calls"], 0)
        self.assertAlmostEqual(line(out, "Revenue Booked")["Total"], -net("sales", date(2025, 4, 1), date(2025, 5, 31)), places=2)

    def test_zoho_down_without_a_copy(self):
        self.zoho.fail = True
        with self.assertRaises(live.ZohoDown):
            self.view()

    def test_single_flight(self):
        zoho = FakeZoho(delay=0.05)
        shared = cache(zoho)
        results = []

        def run():
            results.append(live.statement("PL", self.COLS, SNAPSHOT, OVERRIDES, cache=shared)["zoho_calls"])

        threads = [threading.Thread(target=run) for _ in range(2)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(len(zoho.calls), 3)
        self.assertEqual(sorted(results), [0, 3])

    def test_busy_when_another_fetch_holds_zoho(self):
        self.cache._zoho.acquire()
        try:
            with mock.patch.object(live, "BUSY_WAIT", 0.05), self.assertRaises(live.Busy):
                self.view()
        finally:
            self.cache._zoho.release()


class LimitsTest(unittest.TestCase):
    def test_too_many_calls(self):
        days = [Col(f"d{i}", date(2025, 1, 1) + timedelta(days=2 * i), date(2025, 1, 1) + timedelta(days=2 * i))
                for i in range(40)]
        with mock.patch.object(live, "MAX_CALLS", 50), self.assertRaises(ValueError):
            live.statement("PL", days, SNAPSHOT, OVERRIDES, cache=cache(FakeZoho()))

    def test_reserved_key(self):
        with self.assertRaises(ValueError):
            live.statement("PL", [Col("closing", date(2025, 1, 1), date(2025, 1, 31))], SNAPSHOT, OVERRIDES,
                           cache=cache(FakeZoho()))

    def test_unknown_statement(self):
        with self.assertRaises(ValueError):
            live.statement("CF", periods.month_cols(date(2025, 1, 1), date(2025, 1, 31)), SNAPSHOT, OVERRIDES,
                           cache=cache(FakeZoho()))


class LabelTest(unittest.TestCase):
    def test_labels_match_the_date_filter(self):
        cases = {
            Col("2026-10", date(2026, 10, 1), date(2026, 10, 31)): "Oct-26",
            Col("2026-10", date(2026, 10, 1), date(2026, 10, 15)): "Oct-26 (1–15)",
            Col("q2026-04-01", date(2026, 4, 1), date(2026, 9, 30)): "Apr-26 – Sep-26",
            Col("w2026-10-05", date(2026, 10, 5), date(2026, 10, 11)): "5 – 11 Oct 26",
            Col("w2026-09-28", date(2026, 9, 28), date(2026, 10, 4)): "28 Sep – 4 Oct 26",
            Col("p-1", date(2025, 12, 29), date(2026, 1, 4)): "29 Dec 25 – 4 Jan 26",
            Col("Total", date(2026, 10, 1), date(2026, 10, 15)): "Total",
        }
        for col, want in cases.items():
            self.assertEqual(periods.col_label(col), want)


if __name__ == "__main__":
    unittest.main()
