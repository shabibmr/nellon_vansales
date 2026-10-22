"""`DocSpec` per dataset, in run order. No network, no database.

Plan: docs/sync/transaction-sync-plan.md, "The seven" and "`DocSpec` fields".
`pipeline.py` (not yet built) reads everything that differs between documents
from the spec; it has no `if dataset == …` branches.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable

from . import mapping

HeaderFromList = Callable[[dict[str, Any]], dict[str, Any]]
FromDetail = Callable[[dict[str, Any], dict, dict], tuple[dict[str, Any], list[dict[str, Any]]]]
CollectIds = Callable[[dict[str, Any]], dict[str, set[str]]]


@dataclass(frozen=True)
class OptionalId:
    """An id on a header or line row that is resolved through `masters.ensure`
    before the row is written. `field` is the key on that row; `kind` is the
    `MasterSpec` kind."""

    field: str
    kind: str


@dataclass(frozen=True)
class DocRef:
    """A non-master id that must already exist as a document, checked before
    insert (plan, "Ids": debit note `reference_invoice_id`, vendor credit and
    vendor payment `bill_id`). `field` is read from `line_path` rows when
    `line_path` is set, else from the header. `header_table`/`header_key` name
    where that id must already exist; `kind_value` fills a composite key's
    fixed `kind` column (`purchase_docs (kind, doc_id)`)."""

    field: str
    header_table: str
    header_key: str
    kind_value: str | None = None
    line_path: str | None = None


@dataclass(frozen=True)
class DocSpec:
    dataset: str
    list_path: str
    list_params: dict[str, str]
    list_key: str
    id_field: str
    detail_path: str
    detail_key: str
    cache_folder: str
    header_table: str
    header_key: str | tuple[str, ...]
    line_table: str | None
    line_parent_col: str | None
    line_key: str | None
    line_path: str
    party: str
    header_from_list: HeaderFromList
    from_detail: FromDetail
    collect_ids: CollectIds
    header_optional_ids: tuple[OptionalId, ...] = ()
    line_optional_ids: tuple[OptionalId, ...] = ()
    doc_refs: tuple[DocRef, ...] = ()
    exclude_ids_from: str | None = None
    reroute: Callable[[dict[str, Any]], str | None] | None = None
    has_cogs: bool = False


_SALES_LINE_IDS = (
    OptionalId("item_id", "item"),
    OptionalId("location_id", "location"),
    OptionalId("account_id", "account"),
)
_SALES_HEADER_IDS = (OptionalId("salesperson_id", "salesperson"), OptionalId("location_id", "location"))

DEBIT_NOTES = DocSpec(
    dataset="debit_notes",
    list_path="/invoices",
    list_params={"filter_by": "Type.DebitNote"},
    list_key="invoices",
    id_field="invoice_id",
    detail_path="/invoices/{id}",
    detail_key="invoice",
    cache_folder="debitnotes",
    header_table="debit_notes",
    header_key="debit_note_id",
    line_table="debit_note_lines",
    line_parent_col="debit_note_id",
    line_key="line_item_id",
    line_path="line_items",
    party="customer_id",
    header_from_list=mapping.header_from_list_debit_note,
    from_detail=mapping.from_detail_debit_note,
    collect_ids=mapping.collect_ids_debit_note,
    header_optional_ids=_SALES_HEADER_IDS,
    line_optional_ids=_SALES_LINE_IDS,
    doc_refs=(DocRef("reference_invoice_id", "sales_invoices", "invoice_id"),),
    has_cogs=True,
)

INVOICES = DocSpec(
    dataset="invoices",
    list_path="/invoices",
    list_params={},
    list_key="invoices",
    id_field="invoice_id",
    detail_path="/invoices/{id}",
    detail_key="invoice",
    cache_folder="invoices",
    header_table="sales_invoices",
    header_key="invoice_id",
    line_table="sales_lines",
    line_parent_col="invoice_id",
    line_key="line_item_id",
    line_path="line_items",
    party="customer_id",
    header_from_list=mapping.header_from_list_invoice,
    from_detail=mapping.from_detail_invoice,
    collect_ids=mapping.collect_ids_invoice,
    header_optional_ids=_SALES_HEADER_IDS,
    line_optional_ids=_SALES_LINE_IDS,
    exclude_ids_from="debit_notes",
    reroute=lambda doc: "debit_notes" if mapping.is_debit_note_detail(doc) else None,
    has_cogs=True,
)

_PURCHASE_LINE_IDS = _SALES_LINE_IDS
_PURCHASE_HEADER_IDS = (OptionalId("location_id", "location"),)

BILLS = DocSpec(
    dataset="bills",
    list_path="/bills",
    list_params={},
    list_key="bills",
    id_field="bill_id",
    detail_path="/bills/{id}",
    detail_key="bill",
    cache_folder="bills",
    header_table="purchase_docs",
    header_key=("kind", "doc_id"),
    line_table="purchase_lines",
    line_parent_col="doc_id",
    line_key="line_item_id",
    line_path="line_items",
    party="vendor_id",
    header_from_list=mapping.header_from_list_bill,
    from_detail=mapping.from_detail_bill,
    collect_ids=mapping.collect_ids_bill,
    header_optional_ids=_PURCHASE_HEADER_IDS,
    line_optional_ids=_PURCHASE_LINE_IDS,
)

VENDOR_CREDITS = DocSpec(
    dataset="vendor_credits",
    list_path="/vendorcredits",
    list_params={},
    list_key="vendorcredits",
    id_field="vendor_credit_id",
    detail_path="/vendorcredits/{id}",
    detail_key="vendorcredit",
    cache_folder="vendorcredits",
    header_table="vendor_credits",
    header_key="vendor_credit_id",
    line_table="vendor_credit_lines",
    line_parent_col="vendor_credit_id",
    line_key="line_item_id",
    line_path="line_items",
    party="vendor_id",
    header_from_list=mapping.header_from_list_vendor_credit,
    from_detail=mapping.from_detail_vendor_credit,
    collect_ids=mapping.collect_ids_vendor_credit,
    header_optional_ids=_PURCHASE_HEADER_IDS,
    line_optional_ids=_PURCHASE_LINE_IDS,
    doc_refs=(DocRef("bill_id", "purchase_docs", "doc_id", kind_value="bill"),),
)

SALES_ORDERS = DocSpec(
    dataset="sales_orders",
    list_path="/salesorders",
    list_params={},
    list_key="salesorders",
    id_field="salesorder_id",
    detail_path="/salesorders/{id}",
    detail_key="salesorder",
    cache_folder="salesorders",
    header_table="sales_orders",
    header_key="salesorder_id",
    line_table="sales_order_lines",
    line_parent_col="salesorder_id",
    line_key="line_item_id",
    line_path="line_items",
    party="customer_id",
    header_from_list=mapping.header_from_list_sales_order,
    from_detail=mapping.from_detail_sales_order,
    collect_ids=mapping.collect_ids_sales_order,
    header_optional_ids=_SALES_HEADER_IDS,
    line_optional_ids=_SALES_LINE_IDS,
)

PURCHASE_ORDERS = DocSpec(
    dataset="purchase_orders",
    list_path="/purchaseorders",
    list_params={},
    list_key="purchaseorders",
    id_field="purchaseorder_id",
    detail_path="/purchaseorders/{id}",
    detail_key="purchaseorder",
    cache_folder="purchaseorders",
    header_table="purchase_docs",
    header_key=("kind", "doc_id"),
    line_table="purchase_lines",
    line_parent_col="doc_id",
    line_key="line_item_id",
    line_path="line_items",
    party="vendor_id",
    header_from_list=mapping.header_from_list_purchase_order,
    from_detail=mapping.from_detail_purchase_order,
    collect_ids=mapping.collect_ids_purchase_order,
    header_optional_ids=_PURCHASE_HEADER_IDS,
    line_optional_ids=_PURCHASE_LINE_IDS,
)

VENDOR_PAYMENTS = DocSpec(
    dataset="vendor_payments",
    list_path="/vendorpayments",
    list_params={},
    list_key="vendorpayments",
    id_field="payment_id",
    detail_path="/vendorpayments/{id}",
    detail_key="vendorpayment",
    cache_folder="vendorpayments",
    header_table="vendor_payments",
    header_key="payment_id",
    line_table="vendor_payment_bills",
    line_parent_col="payment_id",
    line_key="bill_payment_id",
    line_path="bills",
    party="vendor_id",
    header_from_list=mapping.header_from_list_vendor_payment,
    from_detail=mapping.from_detail_vendor_payment,
    collect_ids=mapping.collect_ids_vendor_payment,
    header_optional_ids=(OptionalId("location_id", "location"), OptionalId("paid_through_account_id", "account")),
    doc_refs=(DocRef("bill_id", "purchase_docs", "doc_id", kind_value="bill", line_path="bills"),),
)

# Run order (plan, "The seven"): debit notes before invoices, so the invoice
# pass can exclude ids the debit-note pass already claimed.
ALL_SPECS: tuple[DocSpec, ...] = (
    DEBIT_NOTES,
    INVOICES,
    BILLS,
    VENDOR_CREDITS,
    SALES_ORDERS,
    PURCHASE_ORDERS,
    VENDOR_PAYMENTS,
)
