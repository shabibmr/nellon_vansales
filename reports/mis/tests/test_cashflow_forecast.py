"""Cashflow forecast: dated movements and the end-of-day balance."""

from __future__ import annotations

import unittest
from datetime import date

from reports.cashflow_forecast import (
    balances,
    bill_events,
    forecast_from_documents,
    invoice_events,
    opening_accounts,
    purchase_order_events,
    sales_order_events,
)

AS_OF = date(2026, 10, 13)


class OpeningTest(unittest.TestCase):
    def test_leaf_bank_and_cash_only(self) -> None:
        total, rows = opening_accounts([
            {"account_id": "p", "account_name": "Cash On Hand", "account_type": "cash",
             "is_child_present": True, "current_balance": 999},
            {"account_id": "c", "parent_account_id": "p", "account_name": "Till",
             "account_type": "cash", "current_balance": 40},
            {"account_id": "b", "account_name": "Bank", "account_type": "bank", "current_balance": 100.2},
            {"account_id": "z", "account_name": "Zero", "account_type": "bank", "current_balance": 0},
            {"account_id": "s", "account_name": "Stock", "account_type": "stock", "current_balance": 500},
            {"account_id": "n", "account_name": "Petty", "account_type": "cash", "current_balance": -10},
        ])
        self.assertEqual(total, 130.2)
        self.assertEqual([row["name"] for row in rows], ["Bank", "Petty", "Till"])


class MovementTest(unittest.TestCase):
    def test_invoice_and_overdue_bill_dates(self) -> None:
        invoices, pending = invoice_events([
            {"status": "overdue", "balance": 100, "exchange_rate": 3.675, "currency_code": "USD",
             "due_date": "2026-09-01", "invoice_number": "INV-1", "customer_name": "Ada"},
            {"status": "sent", "balance": 50, "exchange_rate": 1, "due_date": "2026-10-20",
             "invoice_number": "INV-2", "customer_name": "Bea"},
            {"status": "paid", "balance": 0, "due_date": "2026-10-01", "invoice_number": "INV-0"},
            {"status": "open", "balance": 5, "invoice_number": "INV-3", "customer_name": "Cy"},
        ], AS_OF)
        self.assertEqual(len(pending), 1)
        self.assertEqual(pending[0]["number"], "INV-3")
        self.assertEqual([(row["number"], row["date"], row["amount"], row["overdue"]) for row in invoices], [
            ("INV-1", "2026-10-13", 367.5, True),
            ("INV-2", "2026-10-20", 50.0, False),
        ])

        bills, _ = bill_events([
            {"status": "overdue", "balance": 10, "exchange_rate": 1, "due_date": "2026-10-01",
             "bill_number": "B-1", "vendor_name": "Mill"},
            {"status": "open", "balance": 4, "exchange_rate": 2, "due_date": "2026-11-01",
             "bill_number": "B-2", "vendor_name": "Mill"},
        ], AS_OF)
        self.assertEqual([(row["number"], row["date"], row["amount"]) for row in bills], [
            ("B-1", "2026-10-13", -10.0),
            ("B-2", "2026-11-01", -8.0),
        ])

    def test_purchase_order_receipt_terms_and_bill_cap(self) -> None:
        events, pending = purchase_order_events([
            {
                "status": "open", "purchaseorder_number": "PO-1", "vendor_name": "Mill",
                "payment_terms": 30, "exchange_rate": 1, "sub_total": 7900, "total": 8295,
                "purchasereceives": [{"date": "2026-05-12", "status": "received"}],
                "bills": [],
                "line_items": [
                    {"quantity": 20, "quantity_billed": 0, "quantity_received": 20, "item_total": 3800},
                    {"quantity": 20, "quantity_billed": 0, "quantity_received": 20, "item_total": 4100},
                ],
            },
            {
                "status": "partially_billed", "purchaseorder_number": "PO-2", "vendor_name": "Mill",
                "payment_terms": 60, "sub_total": 100, "total": 105,
                "bills": [{"status": "paid", "total": 105}],
                "purchasereceives": [{"date": "2026-05-08", "status": "received"}],
                "line_items": [
                    {"quantity": 10, "quantity_billed": 0, "quantity_received": 10, "item_total": 100},
                ],
            },
            {
                "status": "open", "purchaseorder_number": "PO-3", "vendor_name": "Farm",
                "payment_terms": 0, "sub_total": 100, "total": 100,
                "delivery_date": "2026-10-20",
                "purchasereceives": [{"date": "2026-10-10", "status": "received"}],
                "line_items": [
                    {"quantity": 10, "quantity_billed": 0, "quantity_received": 4, "item_total": 100},
                ],
            },
            {
                "status": "open", "purchaseorder_number": "PO-4", "vendor_name": "Farm",
                "sub_total": 10, "total": 10,
                "line_items": [{"quantity": 1, "quantity_billed": 0, "item_total": 10}],
            },
        ], AS_OF)
        by_number = {}
        for row in events:
            by_number.setdefault(row["number"], []).append((row["date"], row["amount"], row["overdue"]))
        self.assertEqual(by_number["PO-1"], [("2026-10-13", -8295.0, True)])
        self.assertNotIn("PO-2", by_number)
        self.assertEqual(by_number["PO-3"], [
            ("2026-10-13", -40.0, True),
            ("2026-10-20", -60.0, False),
        ])
        self.assertEqual(pending[0]["number"], "PO-4")

    def test_sales_order_shipment_plus_terms(self) -> None:
        events, pending = sales_order_events([
            {
                "status": "open", "salesorder_number": "SO-1", "customer_name": "Ada",
                "payment_terms": 15, "shipment_date": "2026-10-10", "sub_total": 200, "total": 210,
                "line_items": [
                    {"quantity": 10, "quantity_invoiced": 4, "quantity_cancelled": 0, "item_total": 200},
                ],
            },
            {"status": "invoiced", "salesorder_number": "SO-2", "total": 50, "sub_total": 50,
             "shipment_date": "2026-10-01", "line_items": [{"quantity": 1, "item_total": 50}]},
            {"status": "open", "salesorder_number": "SO-3", "customer_name": "Bea", "total": 9,
             "sub_total": 9, "line_items": [{"quantity": 1, "quantity_invoiced": 0, "item_total": 9}]},
        ], AS_OF)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["date"], "2026-10-25")
        self.assertEqual(events[0]["amount"], 126.0)
        self.assertFalse(events[0]["overdue"])
        self.assertEqual(pending[0]["number"], "SO-3")


class BalanceTest(unittest.TestCase):
    def test_seeker_days_follow_signed_movements(self) -> None:
        payload = forecast_from_documents(
            as_of=AS_OF,
            currency="AED",
            organization="Nellon",
            accounts=[{"account_id": "b", "account_name": "Bank", "account_type": "bank", "current_balance": 1000}],
            invoices=[{"status": "sent", "balance": 400, "due_date": "2026-10-14",
                       "invoice_number": "INV-2", "customer_name": "Ada"}],
            bills=[{"status": "open", "balance": 100, "due_date": "2026-10-16",
                    "bill_number": "B-1", "vendor_name": "Mill"}],
            mode="test",
            notes=[],
        )
        rows = balances(payload["opening"], payload["events"], AS_OF, date(2026, 10, 16))
        self.assertEqual([row["balance"] for row in rows], [1000.0, 1400.0, 1400.0, 1300.0])
        self.assertEqual(rows[1]["flow"], 400.0)
        self.assertEqual(rows[3]["flow"], -100.0)


if __name__ == "__main__":
    unittest.main()
