# Zoho Data Sync Logic & Implementation Plan

This document outlines the end-to-end synchronization plan for Zoho Books v3 data into the MIS MariaDB database (`nellon_mis`), adhering to the target schema defined in `proposal/DB-Schema-Proposed.md`.

---

## 1. Sync Architecture Overview

The synchronization is split into sequential stages to respect foreign key dependencies and optimize API credit usage:

1. **Stage 1A: Master Data Without `last_modified_time`** (Static / Full Fetch)
2. **Stage 1B: Master Data With `last_modified_time`** (Incremental Delta Fetch)
3. **Stage 2: Transaction Documents (Headers & Lines)**
4. **Stage 3: General Ledger Postings (`gl_journals`)** (Independent Process)

```
┌─────────────────────────────────────────────────────────────┐
│ Stage 1A: Masters Without last_modified_time (Static)       │
│ 1. organization (GET /organizations - once)                 │
│ 2. locations (GET /locations)                               │
│ 3. salespersons (GET /salespersons)                         │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ Stage 1B: Masters With last_modified_time (Incremental)     │
│ 4. accounts (GET /chartofaccounts)                          │
│ 5. customers (GET /contacts?contact_type=customer)          │
│ 6. vendors (GET /contacts?contact_type=vendor)              │
│ 7. vans (GET /cm_salesperson_profile)                       │
│ 8. items & item_units (GET /items, GET /items/{id})         │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ Stage 2: Transaction Documents (Headers & Lines)            │
│ 1. sales_invoices + sales_lines (GET /invoices/{id})        │
│ 2. credit_notes + credit_note_lines (GET /creditnotes/{id}) │
│ 3. debit_notes + debit_note_lines (GET /invoices?Type=Debit)│
│ 4. purchase_docs + purchase_lines (GET /bills, /po)         │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ Stage 3 (Independent): General Ledger Postings              │
│ - gl_journals (GET /chartofaccounts/transactions per acct)  │
│   Summed directly for Trial Balance & P&L reconciliations   │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Stage 1A: Masters Without `last_modified_time` (Static / Full Fetch)

These endpoints do not provide `last_modified_time` in Zoho's response. Because their record counts are very small and change infrequently, they are fetched completely or once:

| Table | Endpoint | Response Characteristics | Sync Strategy |
|---|---|---|---|
| **`organization`** | `GET /organizations` | Static configuration metadata (`organization_id`, `currency_code`, `fiscal_year_start_month`, etc.). | Fetch **once** if table is empty (`organization_id = 783019958`). Do not refetch on subsequent syncs. |
| **`locations`** | `GET /locations` | Returns `location_id`, `location_name`, `is_primary_location`, `is_location_active`, `address`. No timestamp returned. | Full fetch (organization has 7 warehouses/vans). Upsert all rows by `location_id`. |
| **`salespersons`** | `GET /salespersons` | Returns `salesperson_id`, `salesperson_name`, `email`, `is_active`. No timestamp returned. | Full fetch (organization has ~14 salespersons). Upsert all rows by `salesperson_id`. |

---

## 3. Stage 1B: Masters With `last_modified_time` (Incremental Delta Fetch)

These endpoints return `last_modified_time` on every record and accept `last_modified_time` as a query parameter. Only records modified after the latest local `last_modified_time` are queried and upserted:

| Table | Endpoint | Timestamp Field | Incremental Sync Strategy |
|---|---|---|---|
| **`accounts`** | `GET /chartofaccounts` | `last_modified_time` | Query `GET /chartofaccounts?last_modified_time={max_stored}`. Upsert accounts; recompute hierarchy, `pl_bs`, and MIS categories (`category_overrides.csv` takes priority). |
| **`customers`** | `GET /contacts?contact_type=customer` | `last_modified_time` | Query `GET /contacts?contact_type=customer&last_modified_time={max_stored}`. Upsert by `customer_id`. |
| **`vendors`** | `GET /contacts?contact_type=vendor` | `last_modified_time` | Query `GET /contacts?contact_type=vendor&last_modified_time={max_stored}`. Upsert by `vendor_id`. |
| **`vans`** | `GET /cm_salesperson_profile` | `last_modified_time` | Query `GET /cm_salesperson_profile?last_modified_time={max_stored}`. Maps salesperson to van `location_id`, `cf_voucher_prefix`, and `cf_cash_account`. |
| **`items` & `item_units`** | `GET /items`<br>`GET /items/{item_id}` | `last_modified_time` | 1. Query `GET /items?last_modified_time={max_stored}`.<br>2. Upsert `items` header (rates, tax, status).<br>3. For modified items, call `GET /items/{item_id}` to refresh alternate unit conversions into `item_units`. |

---

## 4. Stage 2: Transaction Documents (Headers & Lines)

Document list endpoints provide the IDs and modification timestamps. Complete header amounts, line quantities, rates, and unit conversion IDs are hydrated via the detail endpoints.

### 4.1 Document Header Field Coverage

| Target Table | Source Endpoint | Fields Populated in Header |
|---|---|---|
| **`sales_invoices`** | `GET /invoices/{invoice_id}` | `invoice_id`, `invoice_number`, `date`, `due_date`, `status`, `customer_id`, `customer_name`, `salesperson_id`, `salesperson_name`, `location_id`, `location_name`, `currency_code`, `exchange_rate`, `sub_total`, `discount_total`, `tax_total`, `shipping_charge`, `adjustment`, `total`, `balance`, `net_sales` (AED calc), `cogs` (GL-reconciled; lines are allocated to add up to it), `flagged_lines`, `last_modified_time` |
| **`credit_notes`** | `GET /creditnotes/{creditnote_id}` | `creditnote_id`, `creditnote_number`, `date`, `status`, `customer_id`, `customer_name`, `salesperson_id`, `salesperson_name`, `location_id`, `location_name`, `invoice_id`, `invoice_number`, `reference_number`, `reason`, `currency_code`, `exchange_rate`, `sub_total`, `discount_total`, `tax_total`, `adjustment`, `total`, `balance`, `net_sales` (AED calc), `cogs`, `flagged_lines`, `last_modified_time` |
| **`debit_notes`** | `GET /invoices/{debit_note_id}` (`Type.DebitNote`) | `debit_note_id`, `debit_note_number`, `date`, `due_date`, `status`, `customer_id`, `customer_name`, `salesperson_id`, `salesperson_name`, `location_id`, `location_name`, `reference_invoice_id`, `reference_invoice_number`, `reference_number`, `reason`, `currency_code`, `exchange_rate`, `sub_total`, `discount_total`, `tax_total`, `shipping_charge`, `adjustment`, `total`, `balance`, `net_sales`, `cogs`, `flagged_lines`, `last_modified_time` |
| **`purchase_docs`** | `GET /bills/{bill_id}`<br>`GET /purchaseorders/{po_id}` | `kind`, `doc_id`, `number`, `date`, `due_date`, `expected_delivery_date`, `status`, `billed_status`, `received_status`, `vendor_id`, `vendor_name`, `location_id`, `location_name`, `currency_code`, `exchange_rate`, `reference_number`, `sub_total`, `discount_total`, `tax_total`, `adjustment`, `total`, `balance`, `amount` (AED calc), `flagged_lines`, `last_modified_time` |

### 4.2 Document Line Calculations

1. **Net Sales (AED):**
   - Line ex-tax amount minus line discount, minus allocated document discount (pro-rated by ex-tax line share), converted by header `exchange_rate`.
2. **COGS (AED):**
   - Computed from `purchase_price`, base unit conversion rate (`item_units`), and master `purchase_rate`.
   - Never copied directly from old margin tables or custom fields.
   - Invoice header `cogs` is the Cost of Sales ledger's `inventory_valuation_for_invoice` amount (GL-reconciled); line `cogs` is allocated so the lines add up to it.
   - Credit-note header `cogs` is the ledger's `inventory_valuation_for_credit_notes` amount, stored positive, with lines allocated the same way. Debit notes have no matching ledger type loaded, so they keep the sum of line COGS.
3. **Line Replacement:**
   - On document header update, existing child lines are replaced by matching `line_item_id`.

---

## 5. Stage 3: General Ledger Postings (`gl_journals`)

* **Endpoint:** `GET /chartofaccounts/transactions?account_id={account_id}&per_page=200`
* **Execution:**
  - Iterates over all ledger accounts (skipping group accounts).
  - Can be windowed by `date.start` and `date.end`.
  - Populates `gl_journals` keyed by `(account_id, categorized_transaction_id)`.
  - Independent of document sync; used for Trial Balance, Balance Sheet, and P&L generation.
