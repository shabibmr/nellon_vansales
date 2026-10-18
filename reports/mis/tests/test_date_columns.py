"""Date-range helpers: column parsing, month splitting, coverage merge and gaps (no DB)."""

from __future__ import annotations

import unittest
from datetime import date

from reports import periods
from reports.periods import Col

D = date


class ParseTests(unittest.TestCase):
    def test_parse_cols(self) -> None:
        cols = periods.parse_cols("p-1:2026-08-01:2026-08-31,2026-09:2026-09-01:2026-09-30")
        self.assertEqual(cols, [Col("p-1", D(2026, 8, 1), D(2026, 8, 31)), Col("2026-09", D(2026, 9, 1), D(2026, 9, 30))])
        self.assertEqual(periods.span(cols), (D(2026, 8, 1), D(2026, 9, 30)))

    def test_bad_cols(self) -> None:
        for spec in ("", "a:2026-09-01", "a b:2026-09-01:2026-09-02", "a:2026-09-02:2026-09-01",
                     "a:2026-09-01:2026-09-02,a:2026-10-01:2026-10-02", "a:2026-13-01:2026-13-02",
                     "a:2020-01-01:2026-01-01", ",".join(f"c{i}:2026-01-01:2026-01-02" for i in range(41))):
            with self.subTest(spec=spec), self.assertRaises(ValueError):
                periods.parse_cols(spec)

    def test_cols_span_limit(self) -> None:
        with self.assertRaises(ValueError):
            periods.parse_cols("a:2019-01-01:2019-01-31,b:2026-01-01:2026-01-31")

    def test_parse_range(self) -> None:
        self.assertEqual(periods.parse_range("2026-09-01", "2026-09-01"), (D(2026, 9, 1), D(2026, 9, 1)))
        with self.assertRaises(ValueError):
            periods.parse_range("2026-09-02", "2026-09-01")
        with self.assertRaises(ValueError):
            periods.parse_range(None, "2026-09-01")


class MonthTests(unittest.TestCase):
    def test_month_maths(self) -> None:
        self.assertEqual(periods.month_end("2028-02"), D(2028, 2, 29))
        self.assertEqual(periods.month_end("2026-02"), D(2026, 2, 28))
        self.assertEqual(periods.month_end("2026-12"), D(2026, 12, 31))
        self.assertEqual(periods.add_months("2026-11", 3), "2027-02")
        self.assertEqual(periods.add_months("2026-01", -1), "2025-12")
        self.assertEqual(periods.months_between("2026-11", "2027-01"), ["2026-11", "2026-12", "2027-01"])
        self.assertEqual(periods.months_between("2026-11", "2026-10"), [])

    def test_month_cols_clip_partial_months(self) -> None:
        cols = periods.month_cols(D(2026, 9, 15), D(2026, 10, 15))
        self.assertEqual(cols, [Col("2026-09", D(2026, 9, 15), D(2026, 9, 30)),
                                Col("2026-10", D(2026, 10, 1), D(2026, 10, 15)),
                                Col("Total", D(2026, 9, 15), D(2026, 10, 15))])
        self.assertEqual([c.key for c in periods.month_cols(D(2026, 9, 1), D(2026, 9, 3), total=False)], ["2026-09"])


class CoverageTests(unittest.TestCase):
    def test_merge_overlapping_and_touching(self) -> None:
        self.assertEqual(
            periods.merge_ranges([(D(2026, 10, 13), D(2026, 10, 15)), (D(2026, 9, 1), D(2026, 9, 30)),
                                  (D(2026, 10, 1), D(2026, 10, 12)), (D(2026, 9, 10), D(2026, 9, 12))]),
            [(D(2026, 9, 1), D(2026, 10, 15))])
        self.assertEqual(periods.merge_ranges([(D(2026, 9, 1), D(2026, 9, 2)), (D(2026, 9, 4), D(2026, 9, 5))]),
                         [(D(2026, 9, 1), D(2026, 9, 2)), (D(2026, 9, 4), D(2026, 9, 5))])

    def test_gaps(self) -> None:
        loaded = [(D(2026, 9, 1), D(2026, 9, 30)), (D(2026, 10, 5), D(2026, 10, 15))]
        self.assertEqual(periods.gaps(loaded, D(2026, 8, 30), D(2026, 10, 17)),
                         [(D(2026, 8, 30), D(2026, 8, 31)), (D(2026, 10, 1), D(2026, 10, 4)),
                          (D(2026, 10, 16), D(2026, 10, 17))])
        self.assertEqual(periods.gaps(loaded, D(2026, 9, 3), D(2026, 9, 20)), [])
        self.assertEqual(periods.gaps([], D(2026, 9, 1), D(2026, 9, 2)), [(D(2026, 9, 1), D(2026, 9, 2))])
