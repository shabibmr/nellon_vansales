"""Pure row mappers for Zoho documents and masters. No database, file, network, or print."""

from __future__ import annotations

from decimal import Decimal
from typing import Any

from common.seed_common import d, doc_money, line_cogs, parse_date, parse_dt, resolve_conversion, s


def _flag(val: Any) -> int:
    return 1 if val in (True, 1, "true", "True", "1") else 0


def _blank_to_none(val: str | None) -> str | None:
    return val or None


def map_customer(contact: dict[str, Any]) -> dict[str, Any]:
    return {
        "customer_id": s(contact.get("contact_id"), 40),
        "contact_name": s(contact.get("contact_name") or contact.get("customer_name"), 255),
        "company_name": s(contact.get("company_name"), 255),
        "customer_sub_type": s(contact.get("customer_sub_type"), 50),
        "status": s(contact.get("status") or "active", 20),
        "email": s(contact.get("email"), 255),
        "phone": s(contact.get("phone") or contact.get("mobile"), 50),
        "tax_treatment": s(contact.get("tax_treatment"), 50),
        "tax_reg_no": s(contact.get("tax_reg_no") or contact.get("vat_reg_no"), 50),
        "payment_terms": int(d(contact.get("payment_terms"))),
        "payment_terms_label": s(contact.get("payment_terms_label"), 100),
        "credit_limit": d(contact.get("credit_limit") or contact.get("customer_credit_limit")),
        "currency_code": s(contact.get("currency_code") or "AED", 10),
        "last_modified_time": parse_dt(contact.get("last_modified_time")),
    }


def map_vendor(contact: dict[str, Any]) -> dict[str, Any]:
    return {
        "vendor_id": s(contact.get("contact_id"), 40),
        "contact_name": s(contact.get("contact_name") or contact.get("vendor_name"), 255),
        "company_name": s(contact.get("company_name"), 255),
        "status": s(contact.get("status") or "active", 20),
        "email": s(contact.get("email"), 255),
        "phone": s(contact.get("phone") or contact.get("mobile"), 50),
        "tax_treatment": s(contact.get("tax_treatment"), 50),
        "tax_reg_no": s(contact.get("tax_reg_no") or contact.get("vat_reg_no"), 50),
        "payment_terms": int(d(contact.get("payment_terms"))),
        "payment_terms_label": s(contact.get("payment_terms_label"), 100),
        "currency_code": s(contact.get("currency_code") or "AED", 10),
        "last_modified_time": parse_dt(contact.get("last_modified_time")),
    }


def map_account(account: dict[str, Any]) -> dict[str, Any]:
    """Zoho columns only — MIS category / pl_bs / source stay untouched on update."""
    return {
        "account_id": s(account.get("account_id"), 40),
        "account_code": s(account.get("account_code"), 50),
        "account_name": s(account.get("account_name"), 255),
        "account_type": s(account.get("account_type"), 50),
        "parent_account_id": _blank_to_none(s(account.get("parent_account_id"), 40)),
        "parent_account_name": s(account.get("parent_account_name"), 255),
        "is_active": _flag(account.get("is_active", True)),
        "last_modified_time": parse_dt(account.get("last_modified_time")),
    }


def map_location(location: dict[str, Any]) -> dict[str, Any]:
    address = location.get("address")
    if isinstance(address, dict):
        address = ", ".join(str(v) for v in address.values() if v) or None
    elif address is not None:
        address = str(address) or None
    return {
        "location_id": s(location.get("location_id"), 40),
        "location_name": s(location.get("location_name") or location.get("name"), 255),
        "is_primary": _flag(location.get("is_primary")),
        "address": address,
        "last_modified_time": parse_dt(location.get("last_modified_time")),
    }


def map_salesperson(sp: dict[str, Any]) -> dict[str, Any]:
    return {
        "salesperson_id": s(sp.get("salesperson_id"), 40),
        "salesperson_name": s(sp.get("salesperson_name") or sp.get("name"), 255),
        "email": s(sp.get("email"), 255),
        "phone": s(sp.get("phone") or sp.get("mobile"), 50),
        "status": s(sp.get("status") or "active", 20),
        "last_modified_time": parse_dt(sp.get("last_modified_time")),
    }


def map_item(item: dict[str, Any]) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """Item header plus `item_units` rows from `unit_conversions`. No raw_json."""
    item_id = s(item.get("item_id"), 40)
    header = {
        "item_id": item_id,
        "name": s(item.get("name") or item.get("item_name"), 255),
        "sku": s(item.get("sku"), 100),
        "status": s(item.get("status") or "active", 20),
        "item_type": s(item.get("item_type"), 50),
        "product_type": s(item.get("product_type"), 50),
        "unit": s(item.get("unit"), 40),
        "purchase_rate": d(item.get("purchase_rate")),
        "rate": d(item.get("rate")),
        "account_id": _blank_to_none(s(item.get("account_id"), 40)),
        "account_name": s(item.get("account_name"), 255),
        "purchase_account_id": _blank_to_none(s(item.get("purchase_account_id"), 40)),
        "purchase_account_name": s(item.get("purchase_account_name"), 255),
        "tax_id": s(item.get("tax_id"), 40),
        "tax_name": s(item.get("tax_name"), 100),
        "tax_percentage": d(item.get("tax_percentage")),
        "brand": s(item.get("brand"), 100),
        "track_inventory": _flag(item.get("track_inventory")),
        "can_be_sold": _flag(item.get("can_be_sold", True)),
        "can_be_purchased": _flag(item.get("can_be_purchased", True)),
        "last_modified_time": parse_dt(item.get("last_modified_time")),
    }
    units: list[dict[str, Any]] = []
    for uc in item.get("unit_conversions") or []:
        uid = s(uc.get("unit_conversion_id"), 40)
        if not uid:
            continue
        units.append(
            {
                "unit_conversion_id": uid,
                "item_id": item_id,
                "target_unit": s(uc.get("target_unit"), 50),
                "conversion_rate": d(uc.get("conversion_rate"), "1"),
            }
        )
    return header, units


def build_sales_lines(
    header: dict[str, Any],
    lines: list[dict[str, Any]],
    units: dict,
    rates: dict[str, Decimal],
) -> list[dict[str, Any]]:
    """Build sales_lines-shaped rows from a detail header and its line_items.

    Does not filter unknown customer or item ids — callers NULL those after.
    Each row carries baseline_cogs (own cost) and cogs set to that same value;
    Cost of Sales reconciliation overwrites cogs via apply_cogs.
    """
    money = doc_money(header, lines)
    inv_date = parse_date(header.get("date"))
    invoice_id = s(header.get("invoice_id"), 40)
    built: list[dict[str, Any]] = []

    for ln, m in zip(lines, money):
        lid = s(ln.get("line_item_id"), 40)
        if not lid:
            continue

        qty = d(ln.get("quantity"))
        conv, conv_flag = resolve_conversion(ln, units)
        base_qty = qty * conv
        iid_line = s(ln.get("item_id"), 40) or None
        unit_price = d(ln.get("purchase_price"))
        m_rate = rates.get(iid_line, Decimal("0")) if iid_line else Decimal("0")
        base_unit = s(ln.get("base_unit"), 40)

        cogs_val, c_flag = line_cogs(
            qty=qty,
            conv=conv,
            base_qty=base_qty,
            price=unit_price,
            master_rate=m_rate,
            base_unit=base_unit,
        )
        flags = [f for f in [conv_flag, c_flag] if f]
        flag_str = "; ".join(flags)

        built.append(
            {
                "line_item_id": lid,
                "invoice_id": invoice_id,
                "date": inv_date,
                "location_id": s(ln.get("location_id") or header.get("location_id"), 40) or None,
                "location_name": s(ln.get("location_name") or header.get("location_name"), 255),
                "item_id": iid_line,
                "item_name": s(ln.get("name") or ln.get("item_name") or ln.get("description"), 255),
                "sku": s(ln.get("sku"), 100),
                "account_id": s(ln.get("account_id"), 40) or None,
                "account_name": s(ln.get("account_name"), 255),
                "quantity": qty,
                "unit": s(ln.get("unit"), 40),
                "base_unit": base_unit,
                "conversion_rate": conv,
                "base_quantity": base_qty,
                "rate": d(ln.get("rate")),
                "line_discount": m["line_discount"],
                "invoice_discount": m["doc_discount"],
                "item_total": m["item_total"],
                "tax_amount": m["tax_amount"],
                "net_sales": m["amount"],
                "purchase_price": unit_price,
                "baseline_cogs": cogs_val,
                "cogs": cogs_val,
                "flag": flag_str[:255],
            }
        )
    return built


# ---------------------------------------------------------------------------
# Document specs (zoho_sync/specs.py): header_from_list(row), from_detail(doc,
# units, rates) -> (header_patch, lines), collect_ids(doc) -> {kind: ids}.
#
# `header_from_list` returns only the columns the list row carries (plan,
# "Step 1 — header from the list row"); the pipeline upserts with those keys
# as `update_cols` so detail-only columns on an existing row are left alone,
# and take the table's own default on first insert. `from_detail` returns the
# detail-only header columns plus the built line rows. Header `cogs` is never
# set here — only the Cost of Sales pass writes it. Line `cogs` starts as each
# line's own cost (`line_cogs`) and is overwritten for invoices by that pass.
# ---------------------------------------------------------------------------


def _ids(ids: dict[str, set[str]], kind: str, value: Any) -> None:
    v = s(value, 40)
    if v:
        ids.setdefault(kind, set()).add(v)


def _collect_ids(
    doc: dict[str, Any],
    header_fields: tuple[tuple[str, str], ...],
    line_fields: tuple[tuple[str, str], ...],
    line_path: str = "line_items",
) -> dict[str, set[str]]:
    ids: dict[str, set[str]] = {}
    for field, kind in header_fields:
        _ids(ids, kind, doc.get(field))
    for ln in doc.get(line_path) or []:
        for field, kind in line_fields:
            _ids(ids, kind, ln.get(field))
    return ids


_SALES_LIKE_HEADER_IDS = (("customer_id", "customer"), ("salesperson_id", "salesperson"), ("location_id", "location"))
_ITEM_LINE_IDS = (("item_id", "item"), ("location_id", "location"), ("account_id", "account"))
_PURCHASE_HEADER_IDS = (("vendor_id", "vendor"), ("location_id", "location"))


def collect_ids_invoice(doc: dict[str, Any]) -> dict[str, set[str]]:
    return _collect_ids(doc, _SALES_LIKE_HEADER_IDS, _ITEM_LINE_IDS)


collect_ids_debit_note = collect_ids_invoice
collect_ids_sales_order = collect_ids_invoice


def collect_ids_bill(doc: dict[str, Any]) -> dict[str, set[str]]:
    return _collect_ids(doc, _PURCHASE_HEADER_IDS, _ITEM_LINE_IDS)


collect_ids_purchase_order = collect_ids_bill
collect_ids_vendor_credit = collect_ids_bill


def collect_ids_vendor_payment(doc: dict[str, Any]) -> dict[str, set[str]]:
    header_ids = _PURCHASE_HEADER_IDS + (("paid_through_account_id", "account"),)
    return _collect_ids(doc, header_ids, (), line_path="bills")


# -- Invoices and debit notes: both /invoices, both built with build_sales_lines --


def _invoice_like_header_from_list(
    row: dict[str, Any],
    id_col: str,
    number_col: str,
    *,
    id_field: str = "invoice_id",
    number_field: str = "invoice_number",
) -> dict[str, Any]:
    """List-row header. `id_field`/`number_field` are Zoho list keys; `id_col`/
    `number_col` are the table columns (debit notes keep Zoho's invoice_* keys
    but store under debit_note_*)."""
    return {
        id_col: s(row.get(id_field), 40),
        number_col: s(row.get(number_field), 60),
        "date": parse_date(row.get("date")),
        "due_date": parse_date(row.get("due_date")),
        "status": s(row.get("status"), 30),
        "customer_id": s(row.get("customer_id"), 40) or None,
        "customer_name": s(row.get("customer_name"), 255),
        "salesperson_id": s(row.get("salesperson_id"), 40) or None,
        "salesperson_name": s(row.get("salesperson_name"), 255),
        "location_id": s(row.get("location_id"), 40) or None,
        "location_name": s(row.get("location_name"), 255),
        "currency_code": s(row.get("currency_code") or "AED", 10),
        "exchange_rate": d(row.get("exchange_rate"), "1") or Decimal("1"),
        "total": d(row.get("total")),
        "balance": d(row.get("balance")),
        "shipping_charge": d(row.get("shipping_charge")),
        "adjustment": d(row.get("adjustment")),
        "last_modified_time": parse_dt(row.get("last_modified_time")),
    }


def header_from_list_invoice(row: dict[str, Any]) -> dict[str, Any]:
    return _invoice_like_header_from_list(row, "invoice_id", "invoice_number")


def header_from_list_debit_note(row: dict[str, Any]) -> dict[str, Any]:
    # Zoho debit-note list rows still use invoice_id / invoice_number.
    return _invoice_like_header_from_list(row, "debit_note_id", "debit_note_number")


def _invoice_like_from_detail(
    doc: dict[str, Any],
    units: dict,
    rates: dict[str, Decimal],
    id_col: str,
    discount_col: str,
    extra_header: dict[str, Any],
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    raw_lines = doc.get("line_items") or []
    built = build_sales_lines(doc, raw_lines, units, rates)
    lines = []
    for ln in built:
        row = dict(ln)
        row.pop("baseline_cogs", None)
        row[id_col] = row.pop("invoice_id")
        row[discount_col] = row.pop("invoice_discount")
        lines.append(row)
    net_sales = sum((ln["net_sales"] for ln in lines), Decimal("0"))
    patch = {
        id_col: s(doc.get("invoice_id"), 40),
        "sub_total": d(doc.get("sub_total")),
        "discount_total": d(doc.get("discount_total")),
        "tax_total": d(doc.get("tax_total")),
        "net_sales": net_sales,
        "last_modified_time": parse_dt(doc.get("last_modified_time")),
    }
    patch.update(extra_header)
    return patch, lines


def from_detail_invoice(
    doc: dict[str, Any], units: dict, rates: dict[str, Decimal]
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    return _invoice_like_from_detail(doc, units, rates, "invoice_id", "invoice_discount", {})


def from_detail_debit_note(
    doc: dict[str, Any], units: dict, rates: dict[str, Decimal]
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    extra = {
        "reference_invoice_id": s(doc.get("reference_invoice_id"), 40) or None,
        "reference_invoice_number": s(doc.get("reference_invoice_number"), 60),
        "reference_number": s(doc.get("reference_number"), 100),
        "reason": s(doc.get("reason"), 255),
    }
    return _invoice_like_from_detail(doc, units, rates, "debit_note_id", "note_discount", extra)


def is_debit_note_detail(doc: dict[str, Any]) -> bool:
    """The invoice spec's `reroute` hook: true when a detail fetched as an
    invoice turns out to be a debit note (the list row cannot tell)."""
    return s(doc.get("type"), 20).lower() == "debit_note"


# -- Sales orders: invoice shape, no COGS, quantity_invoiced/order_discount --


def header_from_list_sales_order(row: dict[str, Any]) -> dict[str, Any]:
    return _invoice_like_header_from_list(
        row,
        "salesorder_id",
        "salesorder_number",
        id_field="salesorder_id",
        number_field="salesorder_number",
    )


def from_detail_sales_order(
    doc: dict[str, Any], units: dict, rates: dict[str, Decimal]
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    raw_lines = doc.get("line_items") or []
    shim = dict(doc)
    shim["invoice_id"] = doc.get("salesorder_id")
    built = build_sales_lines(shim, raw_lines, units, rates)
    raw_by_id = {s(ln.get("line_item_id"), 40): ln for ln in raw_lines}
    lines = []
    for ln in built:
        raw = raw_by_id.get(ln["line_item_id"], {})
        row = dict(ln)
        row.pop("baseline_cogs", None)
        row.pop("cogs", None)
        row["salesorder_id"] = row.pop("invoice_id")
        row["order_discount"] = row.pop("invoice_discount")
        row["quantity_invoiced"] = d(raw.get("quantity_invoiced"))
        lines.append(row)
    net_sales = sum((ln["net_sales"] for ln in lines), Decimal("0"))
    patch = {
        "salesorder_id": s(doc.get("salesorder_id"), 40),
        "sub_total": d(doc.get("sub_total")),
        "discount_total": d(doc.get("discount_total")),
        "tax_total": d(doc.get("tax_total")),
        "net_sales": net_sales,
        "last_modified_time": parse_dt(doc.get("last_modified_time")),
    }
    return patch, lines


# -- Bills, purchase orders, vendor credits: doc_money, not build_sales_lines --


def _purchase_doc_header_from_list(row: dict[str, Any], kind: str, id_field: str, number_field: str) -> dict[str, Any]:
    return {
        "kind": kind,
        "doc_id": s(row.get(id_field), 40),
        "number": s(row.get(number_field), 60),
        "date": parse_date(row.get("date")),
        "due_date": parse_date(row.get("due_date")),
        "status": s(row.get("status"), 30),
        "vendor_id": s(row.get("vendor_id"), 40) or None,
        "vendor_name": s(row.get("vendor_name"), 255),
        "location_id": s(row.get("location_id"), 40) or None,
        "location_name": s(row.get("location_name"), 255),
        "currency_code": s(row.get("currency_code") or "AED", 10),
        "exchange_rate": d(row.get("exchange_rate"), "1") or Decimal("1"),
        "reference_number": s(row.get("reference_number"), 100),
        "total": d(row.get("total")),
        "balance": d(row.get("balance")),
        "last_modified_time": parse_dt(row.get("last_modified_time")),
    }


def header_from_list_bill(row: dict[str, Any]) -> dict[str, Any]:
    return _purchase_doc_header_from_list(row, "bill", "bill_id", "bill_number")


def header_from_list_purchase_order(row: dict[str, Any]) -> dict[str, Any]:
    return _purchase_doc_header_from_list(row, "purchase_order", "purchaseorder_id", "purchaseorder_number")


def _purchase_like_lines(
    doc: dict[str, Any],
    units: dict,
    parent_id_field: str,
    parent_id_value: str,
    extra_per_line=None,
) -> list[dict[str, Any]]:
    raw_lines = doc.get("line_items") or []
    money = doc_money(doc, raw_lines)
    dt = parse_date(doc.get("date"))
    out = []
    for ln, m in zip(raw_lines, money):
        lid = s(ln.get("line_item_id"), 40)
        if not lid:
            continue
        qty = d(ln.get("quantity"))
        conv, flag = resolve_conversion(ln, units)
        row = {
            "line_item_id": lid,
            parent_id_field: parent_id_value,
            "date": dt,
            "location_id": s(ln.get("location_id") or doc.get("location_id"), 40) or None,
            "location_name": s(ln.get("location_name") or doc.get("location_name"), 255),
            "item_id": s(ln.get("item_id"), 40) or None,
            "item_name": s(ln.get("name") or ln.get("item_name"), 255),
            "sku": s(ln.get("sku"), 100),
            "account_id": s(ln.get("account_id"), 40) or None,
            "account_name": s(ln.get("account_name"), 255),
            "quantity": qty,
            "unit": s(ln.get("unit"), 40),
            "base_unit": s(ln.get("base_unit"), 40),
            "conversion_rate": conv,
            "base_quantity": qty * conv,
            "rate": d(ln.get("rate")),
            "line_discount": m["line_discount"],
            "doc_discount": m["doc_discount"],
            "item_total": m["item_total"],
            "tax_amount": m["tax_amount"],
            "amount": m["amount"],
            "flag": flag[:255],
        }
        if extra_per_line:
            row.update(extra_per_line(ln, qty))
        out.append(row)
    return out


def from_detail_bill(
    doc: dict[str, Any], units: dict, rates: dict[str, Decimal]
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    doc_id = s(doc.get("bill_id"), 40)
    lines = _purchase_like_lines(
        doc, units, "doc_id", doc_id,
        extra_per_line=lambda ln, qty: {
            "kind": "bill",
            "quantity_received": Decimal("0"),
            "quantity_billed": qty,
            "purchaseorder_item_id": s(ln.get("purchaseorder_item_id"), 40),
        },
    )
    amount = sum((r["amount"] for r in lines), Decimal("0"))
    patch = {
        "kind": "bill",
        "doc_id": doc_id,
        "billed_status": s(doc.get("billed_status"), 30),
        "received_status": s(doc.get("received_status"), 30),
        "expected_delivery_date": parse_date(doc.get("expected_delivery_date")),
        "sub_total": d(doc.get("sub_total")),
        "discount_total": d(doc.get("discount_total")),
        "tax_total": d(doc.get("tax_total")),
        "adjustment": d(doc.get("adjustment")),
        "amount": amount,
        "last_modified_time": parse_dt(doc.get("last_modified_time")),
    }
    return patch, lines


def from_detail_purchase_order(
    doc: dict[str, Any], units: dict, rates: dict[str, Decimal]
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    doc_id = s(doc.get("purchaseorder_id"), 40)
    lines = _purchase_like_lines(
        doc, units, "doc_id", doc_id,
        extra_per_line=lambda ln, qty: {
            "kind": "purchase_order",
            "quantity_received": d(ln.get("quantity_received")),
            "quantity_billed": d(ln.get("quantity_billed")),
            "purchaseorder_item_id": s(ln.get("purchaseorder_item_id"), 40),
        },
    )
    amount = sum((r["amount"] for r in lines), Decimal("0"))
    patch = {
        "kind": "purchase_order",
        "doc_id": doc_id,
        "billed_status": s(doc.get("billed_status"), 30),
        "received_status": s(doc.get("received_status"), 30),
        "expected_delivery_date": parse_date(doc.get("expected_delivery_date")),
        "sub_total": d(doc.get("sub_total")),
        "discount_total": d(doc.get("discount_total")),
        "tax_total": d(doc.get("tax_total")),
        "adjustment": d(doc.get("adjustment")),
        "amount": amount,
        "last_modified_time": parse_dt(doc.get("last_modified_time")),
    }
    return patch, lines


def header_from_list_vendor_credit(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "vendor_credit_id": s(row.get("vendor_credit_id"), 40),
        "vendor_credit_number": s(row.get("vendor_credit_number"), 60),
        "date": parse_date(row.get("date")),
        "status": s(row.get("status"), 30),
        "vendor_id": s(row.get("vendor_id"), 40) or None,
        "vendor_name": s(row.get("vendor_name"), 255),
        "location_id": s(row.get("location_id"), 40) or None,
        "location_name": s(row.get("location_name"), 255),
        "reference_number": s(row.get("reference_number"), 100),
        "currency_code": s(row.get("currency_code") or "AED", 10),
        "exchange_rate": d(row.get("exchange_rate"), "1") or Decimal("1"),
        "total": d(row.get("total")),
        "balance": d(row.get("balance")),
        "last_modified_time": parse_dt(row.get("last_modified_time")),
    }


def from_detail_vendor_credit(
    doc: dict[str, Any], units: dict, rates: dict[str, Decimal]
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    vc_id = s(doc.get("vendor_credit_id"), 40)
    lines = _purchase_like_lines(doc, units, "vendor_credit_id", vc_id)
    amount = sum((r["amount"] for r in lines), Decimal("0"))
    patch = {
        "vendor_credit_id": vc_id,
        "kind": "bill",
        "bill_id": s(doc.get("bill_id"), 40) or None,
        "sub_total": d(doc.get("sub_total")),
        "discount_total": d(doc.get("discount_total")),
        "tax_total": d(doc.get("tax_total")),
        "adjustment": d(doc.get("adjustment")),
        "amount": amount,
        "last_modified_time": parse_dt(doc.get("last_modified_time")),
    }
    return patch, lines


# -- Vendor payments: no item lines; bills[] -> vendor_payment_bills --


def header_from_list_vendor_payment(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "payment_id": s(row.get("payment_id"), 40),
        "payment_number": s(row.get("payment_number"), 60),
        "date": parse_date(row.get("date")),
        "vendor_id": s(row.get("vendor_id"), 40) or None,
        "vendor_name": s(row.get("vendor_name"), 255),
        "location_id": s(row.get("location_id"), 40) or None,
        "location_name": s(row.get("location_name"), 255),
        "payment_mode": s(row.get("payment_mode"), 60),
        "reference_number": s(row.get("reference_number"), 100),
        "currency_code": s(row.get("currency_code") or "AED", 10),
        "exchange_rate": d(row.get("exchange_rate"), "1") or Decimal("1"),
        "amount": d(row.get("amount")),
        "last_modified_time": parse_dt(row.get("last_modified_time")),
    }


def from_detail_vendor_payment(
    doc: dict[str, Any], units: dict, rates: dict[str, Decimal]
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    payment_id = s(doc.get("payment_id"), 40)
    lines = []
    for b in doc.get("bills") or []:
        bpid = s(b.get("bill_payment_id"), 40)
        if not bpid:
            continue
        lines.append(
            {
                "bill_payment_id": bpid,
                "payment_id": payment_id,
                "kind": "bill",
                "bill_id": s(b.get("bill_id"), 40),
                "amount_applied": d(b.get("amount_applied") or b.get("amount")),
                "tax_amount_withheld": d(b.get("tax_amount_withheld")),
            }
        )
    patch = {
        "payment_id": payment_id,
        "balance": d(doc.get("balance")),
        "tax_amount_withheld": d(doc.get("tax_amount_withheld")),
        "paid_through_account_id": s(doc.get("paid_through_account_id"), 40) or None,
        "paid_through_account_name": s(doc.get("paid_through_account_name"), 255),
        "last_modified_time": parse_dt(doc.get("last_modified_time")),
    }
    return patch, lines
