# Sales, purchases, and master tables

Clean document tables for sales revenue and purchases. One row per Zoho document, keyed by the Zoho id. No `run_id`.

`last_modified_time` is stored on the header only. Zoho keeps that timestamp on the document, and a line changes only when its document changes.

Header money fields (`sub_total`, `discount_total`, `tax_total`, `adjustment`, `total`, `balance`, and `shipping_charge` on a sales invoice) stay in the document currency, as Zoho reports them. `net_sales`, `cogs`, and `amount` are in AED. Line discounts are in AED and exclude tax.

Draft and void documents stay in the tables. Revenue reports skip them. Purchase reports also skip cancelled documents.

Vendor credits are not in these tables. A customer credit note reduces sales. A customer debit note increases sales. Both are stored as positive amounts on their own tables. Net sales is invoices, plus debit notes, minus credit notes. Net COGS uses the same signs.

## sales_invoices

One row per Zoho invoice. Primary key `invoice_id`.

| Column | What it holds |
|---|---|
| `invoice_id` | Zoho invoice id |
| `invoice_number`, `date`, `due_date`, `status` | Document |
| `customer_id`, `customer_name` | Customer. `customer_id` references `customers` |
| `salesperson_id`, `salesperson_name` | Salesperson. `salesperson_id` references `salespersons` |
| `location_id`, `location_name` | Company location on the invoice header. This is not the van |
| `currency_code`, `exchange_rate` | Currency |
| `sub_total`, `discount_total`, `tax_total`, `shipping_charge`, `adjustment`, `total`, `balance` | Zoho header amounts, invoice currency |
| `net_sales` | Revenue in AED, after discount, excluding tax |
| `cogs` | Invoice COGS in AED. Sum of `sales_lines.cogs` |
| `flagged_lines` | Count of lines with a flag |
| `last_modified_time` | Later fetch replaces this invoice |

## sales_lines

One row per Zoho invoice line. Primary key `line_item_id`. `invoice_id` references `sales_invoices`.

| Column | What it holds |
|---|---|
| `line_item_id` | Zoho line item id |
| `invoice_id` | Parent invoice |
| `date` | Invoice date |
| `location_id`, `location_name` | Warehouse or van on this line. `location_id` references `locations`. The margin report calls this the van |
| `item_id`, `item_name`, `sku`, `account_id`, `account_name` | Item and income account. `account_id` references `accounts` |
| `quantity`, `unit` | Quantity in the unit on the invoice |
| `base_unit`, `conversion_rate`, `base_quantity` | Base quantity. These do not change the sales amount |
| `rate` | Selling rate, invoice currency |
| `line_discount` | Line discount, AED, excluding tax |
| `invoice_discount` | This line’s share of the invoice discount, AED, excluding tax |
| `item_total`, `tax_amount` | Line amounts, invoice currency |
| `net_sales` | Line revenue in AED, excluding tax, after both discounts |
| `purchase_price` | Zoho’s price on the line, as Zoho stored it |
| `cogs` | Line COGS in AED |
| `flag` | Review note, for example `unknown unit conversion` |

`net_sales` and `cogs` on the lines of an invoice add up to the same columns on the header. `invoice_discount` on the lines adds up to the header discount once it is converted to AED. Revenue is `quantity × rate` in the unit sold. A 40 kg bag sold at 196 is 196 of revenue. The conversion to kg is only for quantity.

## purchase_docs

One row per Zoho bill or purchase order. Primary key (`kind`, `doc_id`).

| Column | What it holds |
|---|---|
| `kind` | `bill` or `purchase_order` |
| `doc_id` | Zoho `bill_id` or `purchaseorder_id` |
| `number` | `bill_number` or `purchaseorder_number` |
| `date`, `due_date` | Document date. `due_date` is the bill due date |
| `expected_delivery_date` | Purchase order delivery date |
| `status` | Zoho status |
| `billed_status`, `received_status` | Purchase order progress |
| `vendor_id`, `vendor_name` | Vendor. `vendor_id` references `vendors` |
| `location_id`, `location_name` | Location on the document. `location_id` references `locations` |
| `currency_code`, `exchange_rate` | Currency |
| `reference_number` | Vendor reference on the bill |
| `sub_total`, `discount_total`, `tax_total`, `adjustment`, `total`, `balance` | Zoho header amounts, document currency |
| `amount` | Purchase amount in AED, after discount, excluding tax. Sum of `purchase_lines.amount` |
| `flagged_lines` | Count of lines with a flag |
| `last_modified_time` | Zoho timestamp on the document |

## purchase_lines

One row per Zoho bill or purchase-order line. Primary key `line_item_id`. (`kind`, `doc_id`) references `purchase_docs`.

| Column | What it holds |
|---|---|
| `line_item_id` | Zoho line item id |
| `kind`, `doc_id` | Parent document |
| `date` | Document date |
| `location_id`, `location_name` | Warehouse on this line. `location_id` references `locations` |
| `item_id`, `item_name`, `sku`, `account_id`, `account_name` | Item and purchase account. `account_id` references `accounts` |
| `quantity`, `unit` | Quantity in the unit on the document |
| `quantity_received`, `quantity_billed` | Purchase-order progress. On a bill, `quantity` is the billed quantity |
| `base_unit`, `conversion_rate`, `base_quantity` | Base quantity. These do not change the amount |
| `rate` | Rate, document currency |
| `line_discount`, `doc_discount` | Discounts in AED, excluding tax. `doc_discount` is this line’s share of the document discount |
| `item_total`, `tax_amount` | Line amounts, document currency |
| `amount` | Line amount in AED, excluding tax, after both discounts |
| `purchaseorder_item_id` | On a bill line, the purchase-order line it came from |
| `flag` | Review note, for example `unknown unit conversion` |

`amount` on the lines adds up to `amount` on the header. `doc_discount` on the lines adds up to the header discount once it is converted to AED. There is no COGS column. The purchase amount is the cost.

## credit_notes

One row per Zoho customer credit note. Primary key `creditnote_id`. No database has this table. Load it from `GET /creditnotes`, then `GET /creditnotes/{creditnote_id}`.

| Column | What it holds |
|---|---|
| `creditnote_id` | Zoho credit note id |
| `creditnote_number`, `date`, `status` | Document. Status is `draft`, `open`, `closed`, or `void` |
| `customer_id`, `customer_name` | Customer. `customer_id` references `customers` |
| `salesperson_id`, `salesperson_name` | Salesperson. `salesperson_id` references `salespersons` |
| `location_id`, `location_name` | Company location on the header. This is not the van |
| `invoice_id`, `invoice_number` | Invoice this credit note was raised against. `invoice_id` references `sales_invoices` when that invoice is loaded |
| `reference_number` | Zoho reference |
| `reason` | Zoho `reason_for_credit_debit_note` |
| `currency_code`, `exchange_rate` | Currency |
| `sub_total`, `discount_total`, `tax_total`, `adjustment`, `total`, `balance` | Zoho header amounts, document currency |
| `net_sales` | Amount in AED that reduces revenue, after discount, excluding tax |
| `cogs` | Amount in AED that reduces COGS. Sum of `credit_note_lines.cogs` |
| `flagged_lines` | Count of lines with a flag |
| `last_modified_time` | Later fetch replaces this credit note |

## credit_note_lines

One row per Zoho credit-note line. Primary key `line_item_id`. `creditnote_id` references `credit_notes`.

| Column | What it holds |
|---|---|
| `line_item_id` | Zoho line item id |
| `creditnote_id` | Parent credit note |
| `invoice_id`, `invoice_item_id` | Original invoice and its `sales_lines.line_item_id`, when Zoho sends them |
| `date` | Credit-note date |
| `location_id`, `location_name` | Warehouse or van on this line. `location_id` references `locations` |
| `item_id`, `item_name`, `sku`, `account_id`, `account_name` | Item and income account. `account_id` references `accounts` |
| `quantity`, `unit` | Quantity in the unit on the credit note |
| `base_unit`, `conversion_rate`, `base_quantity` | Base quantity. These do not change the sales amount |
| `rate` | Rate, document currency |
| `line_discount`, `note_discount` | Discounts in AED, excluding tax. `note_discount` is this line’s share of the credit-note discount |
| `item_total`, `tax_amount` | Line amounts, document currency |
| `net_sales` | Line amount in AED that reduces revenue, excluding tax, after both discounts |
| `purchase_price` | Zoho’s price on the line, as Zoho stored it. Empty when the line has none |
| `cogs` | Line amount in AED that reduces COGS |
| `flag` | Review note |

`net_sales` and `cogs` on the lines add up to the same columns on the header. A saved list page holds 200 credit notes, numbered `KGT-CN-*`, dated 12 May 2026 through 15 Aug 2026. That page is not the full set. The Cost of Sales ledger has valuations for 257 credit notes from 18 Mar 2026 through 12 Oct 2026, a credit of 266,789.30.

## debit_notes

One row per Zoho customer debit note. Primary key `debit_note_id`. No database has this table. Zoho stores a debit note as an invoice. List them with `GET /invoices?filter_by=Type.DebitNote`. The detail is `GET /invoices/{debit_note_id}`.

| Column | What it holds |
|---|---|
| `debit_note_id` | Zoho id. The payload calls this `invoice_id` |
| `debit_note_number`, `date`, `due_date`, `status` | Document. The payload calls the number `invoice_number`. Status uses the invoice statuses |
| `customer_id`, `customer_name` | Customer. `customer_id` references `customers` |
| `salesperson_id`, `salesperson_name` | Salesperson. `salesperson_id` references `salespersons` |
| `location_id`, `location_name` | Company location on the header. This is not the van |
| `reference_invoice_id`, `reference_invoice_number` | Original invoice this debit note adjusts. `reference_invoice_id` references `sales_invoices` when that invoice is loaded |
| `reference_number` | Zoho reference |
| `reason` | Zoho `reason_for_credit_debit_note` |
| `currency_code`, `exchange_rate` | Currency |
| `sub_total`, `discount_total`, `tax_total`, `shipping_charge`, `adjustment`, `total`, `balance` | Zoho header amounts, document currency |
| `net_sales` | Amount in AED that increases revenue, after discount, excluding tax |
| `cogs` | Amount in AED that increases COGS. Sum of `debit_note_lines.cogs` |
| `flagged_lines` | Count of lines with a flag |
| `last_modified_time` | Later fetch replaces this debit note |

## debit_note_lines

One row per Zoho debit-note line. Primary key `line_item_id`. `debit_note_id` references `debit_notes`.

| Column | What it holds |
|---|---|
| `line_item_id` | Zoho line item id |
| `debit_note_id` | Parent debit note |
| `date` | Debit-note date |
| `location_id`, `location_name` | Warehouse or van on this line. `location_id` references `locations` |
| `item_id`, `item_name`, `sku`, `account_id`, `account_name` | Item and income account. `account_id` references `accounts` |
| `quantity`, `unit` | Quantity in the unit on the debit note |
| `base_unit`, `conversion_rate`, `base_quantity` | Base quantity. These do not change the sales amount |
| `rate` | Rate, document currency |
| `line_discount`, `note_discount` | Discounts in AED, excluding tax |
| `item_total`, `tax_amount` | Line amounts, document currency |
| `net_sales` | Line amount in AED that increases revenue, excluding tax, after both discounts |
| `purchase_price` | Zoho’s price on the line, as Zoho stored it. Empty when the line has none |
| `cogs` | Line amount in AED that increases COGS |
| `flag` | Review note |

`net_sales` and `cogs` on the lines add up to the same columns on the header. There is no local debit-note file to count. Do not fill this table from the ledger type `inventory_valuation_for_debit_notes`. Those 44 rows are vendor credits numbered `KGT-VC-*`, and each id also appears as `vendor_credit`.

## organization

One row for this Zoho organisation. Primary key `organization_id`. Fetched once, from `GET /organizations`, and not refreshed on later syncs.

| Column | What it holds |
|---|---|
| `organization_id` | Zoho organisation id. This company is `783019958` |
| `name` | `KOYSON GENERAL TRADING LLC` |
| `currency_id` | Zoho currency id of the base currency, `3331482000000075111` |
| `currency_code` | Base currency. `AED` |
| `currency_symbol` | `AED` |
| `currency_format` | `###,##0.00` |
| `fiscal_year_start_month` | Month the books year starts, numbered 1 to 12. January is 1 |
| `time_zone` | `Asia/Dubai` |
| `country`, `country_code` | `U.A.E`, `AE` |
| `is_tax_registered` | This company is registered for tax |
| `synced_at` | When this one fetch was stored |

`nellon_mis` and `nellon_mis_dev` already hold this row, synced at 2026-10-13 20:45:59. `nellon_mis_test` has the table and no row. The current column `fiscal_year_start_month` is blank. Zoho sent `0`, and the loader treats 0 as empty. Zoho's 0 means January, so the value to store is 1. The current table also keeps the whole payload in `raw`. This row does not.

Document amounts in AED are already in this currency. A document in another currency converts with its own `exchange_rate`. The organisation default is tax-exclusive. A document with `is_inclusive_tax` still uses the inclusive rule.

## accounts

One row per Zoho chart-of-accounts record. Primary key `account_id`. This replaces `category_master`. The reporting category stays on the same row, so profit and loss and the balance sheet still read `pl_bs`, `category`, and `sub_category` from here.

| Column | What it holds |
|---|---|
| `account_id` | Zoho account id |
| `account_code` | Account code, for example `5.1.1000` |
| `account_name` | Zoho account name. `category_master` calls this `ledger_name` |
| `account_type` | Zoho type, for example `income`, `expense`, `cost_of_goods_sold` |
| `parent_account_id` | Parent account. Empty on a top-level account |
| `parent_account_name` | Parent name, copied so a list does not need a join |
| `group_ledger` | `Group` when another account names this one as its parent. Otherwise `Ledger` |
| `is_active` | Zoho active flag |
| `pl_bs` | `PL` or `BS` |
| `category`, `sub_category` | MIS reporting line |
| `source` | What set the category: `override`, `rule`, `type`, or `review` |
| `note` | Why the category was chosen, or the review reason |
| `last_modified_time` | Zoho timestamp on the account |

`group_ledger`, `pl_bs`, `category`, `sub_category`, `source`, and `note` are MIS fields. Zoho does not send them. A hand edit in `category_overrides.csv` wins, then the name rules, then the parent chain, then `account_type`. A row with `source = review` still has a suggested category.

`current_balance` stays off this table. A balance is a general-ledger figure and changes with every posting. `gl_monthly` holds the movement.

## gl_monthly

One row per account per month. Primary key (`account_id`, `month`). `account_id` references `accounts`. This replaces `tb_accounts` and `tb_monthly`. The name, type, and category stay on `accounts`.

| Column | What it holds |
|---|---|
| `account_id` | Zoho account id |
| `month` | `YYYY-MM`. The row `0000-00` is the baseline: all movement before the first month stored |
| `debit` | Debit total for that month, in AED. Empty when only `net` is known |
| `credit` | Credit total for that month, in AED. Empty when only `net` is known |
| `net` | `debit − credit`. Debit-positive: a debit is positive and a credit is negative |
| `synced_at` | When this month was fetched |

Zoho's `GET /reports/generalledger` returns the movement for the dates you ask for. It does not return an opening balance. Opening and closing are sums of these rows, built when a report is read.

`nellon_mis` and `nellon_mis_dev` hold the same financials run, 1 Apr 2026 through 30 Sep 2026: 169 accounts and 635 month rows. Each month's nets add up to 0.00. `nellon_mis_test` has the tables and no rows. `tb_monthly` stores `net` only. Debit and credit are kept for the whole six-month run, not for each month, so that run can seed `net` and cannot seed `debit` or `credit`.

A balance-sheet opening is the baseline plus every month before the report. A profit-and-loss opening counts only the months since 1 January of the report's year. The profit and loss from the baseline, which is every year before that January, is one synthetic balance-sheet row, account id `__prior_years_pl__`, named "Prior years P&L (retained)", under Reserves and surplus. That row is computed when the report is built. It is not a Zoho account and it is not stored in `gl_monthly`.

`cost_of_sales_nellon` and `inventory_postings` stay the posting-level ledger for those accounts. `gl_monthly` does not replace them.

## items

One row per Zoho item. Primary key `item_id`. This replaces the current `items` table. `purchase_rate` and `rate` are per base unit (`unit`), not per bag or carton.

| Column | What it holds |
|---|---|
| `item_id` | Zoho item id |
| `name`, `sku` | Item |
| `status` | `active` or `inactive` |
| `item_type`, `product_type` | For example `inventory` / `goods`, or `sales_and_purchases` / `service` |
| `unit` | Base unit, for example `kg` or `pcs` |
| `purchase_rate` | Master purchase rate per base unit |
| `rate` | Master selling rate per base unit |
| `account_id`, `account_name` | Default sales account. `account_id` references `accounts` |
| `purchase_account_id`, `purchase_account_name` | Default purchase account. `purchase_account_id` references `accounts` |
| `tax_id`, `tax_name`, `tax_percentage` | Default sales tax |
| `brand` | Brand |
| `track_inventory`, `can_be_sold`, `can_be_purchased` | Zoho flags |
| `last_modified_time` | Zoho timestamp on the item |

`stock_on_hand` and `available_stock` stay off this table. They change with every receipt and invoice. The current `items.raw_json` is the item-list payload and does not contain unit conversions, so those live in `item_units`.

## item_units

One row per alternate unit on an item. Primary key `unit_conversion_id`. `item_id` references `items`.

| Column | What it holds |
|---|---|
| `unit_conversion_id` | Zoho unit conversion id. The same id is on an invoice or bill line |
| `item_id` | Parent item |
| `target_unit` | Sale or purchase unit, for example `40 KG BAG` |
| `conversion_rate` | Base units in one `target_unit`. A line's base quantity is `quantity × conversion_rate` |

The rate does not change the sales amount or the purchase amount. It changes quantity, and it changes COGS only when the line price is a base-unit price. A missing `unit_conversion_id` is the `unknown unit conversion` flag on the document line.

## locations

One row per Zoho location. Primary key `location_id`. The van-sales app calls these warehouses. No database has this table today. Margin stores the line location name in a column called `van`.

| Column | What it holds |
|---|---|
| `location_id` | Zoho location id |
| `location_name` | Name, for example `YOONUS` or `Koyson General Trading LLC (Warehouse)` |
| `is_primary` | The organisation's main location. On the invoices in cache, the header location is always this one |
| `address` | Address |
| `last_modified_time` | Zoho timestamp on the location |

On 2,504 cached invoices the header location is always `Koyson General Trading LLC`. The line uses one of seven locations. Three of those are named after a salesperson (`YOONUS`, `SHINAD`, `MANSOOR`). The other four are warehouses.

## salespersons

One row per Zoho salesperson. Primary key `salesperson_id`. No database has this table today. Margin stores the name only.

| Column | What it holds |
|---|---|
| `salesperson_id` | Zoho salesperson id |
| `salesperson_name` | Name |
| `email` | Zoho salesperson email. Often empty |
| `phone` | Phone from `cm_salesperson_profile`, when that profile exists |
| `status` | `active` or `inactive` |
| `last_modified_time` | Zoho timestamp on the salesperson |

The cached invoices use 14 salespersons. The name on an invoice is not the van. `SHAMEER TAYYIL&HASHIM` invoices are stocked from `78352-HASHIM AL QUISIS (Warehouse)`, and several salespersons share `Koyson General Trading LLC (Warehouse)`.

## customers

One row per Zoho customer. Primary key `customer_id`, which is the contact id. No database has this table. Load it from `GET /contacts?contact_type=customer`.

| Column | What it holds |
|---|---|
| `customer_id` | Zoho `contact_id` |
| `contact_name` | Name printed on the invoice as `customer_name` |
| `company_name` | Registered company name |
| `customer_sub_type` | `business` or `individual` |
| `status` | `active` or `inactive` |
| `email`, `phone` | Contact |
| `tax_treatment`, `tax_reg_no` | UAE tax treatment and TRN |
| `payment_terms`, `payment_terms_label` | Credit days and the label, for example Net 15 |
| `credit_limit` | Credit limit set on the contact. This is a setting, not the amount owed |
| `currency_code` | Contact currency |
| `last_modified_time` | Zoho timestamp on the contact |

The loaded invoices use 455 customer names and, where the id was stored, more contact ids than names. Seven names belong to more than one contact. `CASH CUSTOMER` is two contacts, `3331482000000342015` and `3331482000186533009`. Join on `customer_id`. Run 6 stored the name and left `customer_id` blank, so those rows cannot be joined.

## vendors

One row per Zoho vendor. Primary key `vendor_id`, which is the contact id. No database has this table. Load it from `GET /contacts?contact_type=vendor`.

| Column | What it holds |
|---|---|
| `vendor_id` | Zoho `contact_id` |
| `contact_name` | Name printed on the bill as `vendor_name` |
| `company_name` | Registered company name |
| `status` | `active` or `inactive` |
| `email`, `phone` | Contact |
| `tax_treatment`, `tax_reg_no` | UAE tax treatment and TRN |
| `payment_terms`, `payment_terms_label` | Payment days and the label |
| `currency_code` | Contact currency |
| `last_modified_time` | Zoho timestamp on the contact |

The loaded purchase lines use 103 vendor names and do not store a vendor id. The same display name can exist once as a customer and once as a vendor. Those are two contact ids. Do not merge them by name.

## vans

One row per van. Primary key `location_id`. Zoho has no van record. A van is a location assigned to a salesperson in `cm_salesperson_profile`.

| Column | What it holds |
|---|---|
| `location_id` | The van's location. References `locations` |
| `salesperson_id` | Salesperson who runs this van. References `salespersons`. Empty when the location is not assigned |
| `voucher_prefix` | Document-number prefix for this van, from the salesperson profile |
| `cash_account_id`, `cash_account_name` | This salesperson's cash ledger (`cf_cash_account`). `cash_account_id` references `accounts` |

A location that is only a warehouse stays in `locations` and has no `vans` row. The invoice line's `location_id` is the van when that location is in `vans`.

## Left out on purpose

These are calculated, copied from the header, or belong to another table:

- `month`, `line_count`, header `base_quantity`, `gross_margin`, and `cost_rate`
- Account name, category, opening, and closing copied onto each general-ledger row. Opening and closing are sums of `gl_monthly`
- `customer_name`, `salesperson_name`, and `invoice_number` repeated on every sales line
- `run_id` and `line_no`
- `cost_source`
- `fetched_at` (the time a row was written here). The header keeps Zoho’s `last_modified_time`
- On the chart: `entity_name`, `concate`, `path`, `depth`, and `current_balance`. The organisation name lives on `organization`. `path` and `depth` are rebuilt from `parent_account_id`. `updated_at` on `category_master` is the local write time; the chart keeps Zoho’s `last_modified_time`
- On the item: `description`, `raw_json`, `fetched_at`, `stock_on_hand`, and `available_stock`
- A separate van id. The current `margin_invoices.van` and `margin_lines.van` columns are the line location name
- On a contact: `outstanding_receivable_amount`, `outstanding_payable_amount`, route, GPS, and contact persons. The amounts change with every invoice, bill, and payment. Route and GPS belong to the van-sales app
- The organisation payload in `organization.raw`. The base currency and the fiscal-year month are columns

`cost_of_sales_nellon` stays the Cost of Sales ledger. One invoice can have more than one posting, so `sales_invoices.cogs` does not replace it. `inventory_postings` stays the inventory asset side.

## Sync

These are the rules for loading the tables. They come from the current MariaDB tables, the invoice cache, and the van-sales app.

### Order

Load masters before documents. The organisation is the exception: fetch it once and then leave it.

1. `organization` from `GET /organizations`, only when the table is empty.
2. `accounts` from `GET /chartofaccounts`.
3. `customers` from `GET /contacts?contact_type=customer`, and `vendors` from `GET /contacts?contact_type=vendor`.
4. `locations` from `GET /locations`.
5. `salespersons` from `GET /salespersons`.
6. `vans` from `cm_salesperson_profile`, after locations, salespersons, and accounts exist.
7. `items` from `GET /items`, then `GET /items/{id}` for `item_units`.
8. Invoice detail, then its `sales_lines`. Exclude debit notes from this list.
9. Credit-note detail, then its `credit_note_lines`.
10. Debit-note detail, then its `debit_note_lines`.
11. Bill detail and purchase-order detail, then their `purchase_lines`.

`GET /journals` does not feed these tables. That endpoint returns manual journals and leaves out invoices, bills, credit notes, debit notes, expenses, and receipts.

`cost_of_sales_nellon` and `inventory_postings` stay a separate load from `GET /chartofaccounts/transactions`. That load does not write `sales_invoices.cogs` or `gl_monthly`.

`gl_monthly` is its own load, after `accounts` and `organization`. One `GET /reports/generalledger` call per calendar month, plus one call for the baseline. It does not wait on the invoices or the bills.

### Organisation

`GET /organizations` returns every organisation this token can see. Keep the one whose `organization_id` is `783019958`. If `organization` already has a row, do not call Zoho again.

Store `currency_code` AED as the base currency. `fiscal_year_start_month` arrives as `0`. Store `1`. January is month 1. Do not use `value or ""` for that field, because 0 is a real month and the current column was saved blank.

The profit-and-loss year starts in January. Amounts stored as AED are in this base currency. A document whose `currency_code` is not AED is converted with that document's `exchange_rate`.

### Replace a row

Upsert a header when Zoho's `last_modified_time` is newer than the stored value. The same test applies to an account, an item, a location, and a salesperson.

A line has no timestamp. When a document is replaced, upsert its lines by `line_item_id` and delete lines of that document that are no longer in the payload. Do the same for `item_units` when an item is replaced. Do not key a line by `line_no`, and do not insert another copy because a report was run again.

`fetched_at` on the current tables is the time the row was written locally. It is not the test for skipping a fetch.

### Read the cache the same way

`output/cache/invoices/{invoice_id}.json` is the invoice object. `output/oct_fetch/{invoice_id}.json` is `{"invoice": {...}}`. Use the `invoice` value only when it is an object. Treating every file as wrapped drops the line items.

`items.raw_json` is the item-list payload. None of the 1,137 stored payloads contains `unit_conversions`. The 95 item-detail files in `output/cache/items/` do. A sync that stops at the list cannot fill `item_units`.

### Accounts

Store `parent_account_id`. The current `category_master` stores the parent name only, and 275 of 357 accounts have a parent id on the chart payload.

A Zoho refresh updates the Zoho columns: code, name, type, parent, and `is_active`. It recomputes `group_ledger`, `pl_bs`, `category`, `sub_category`, `source`, and `note` with the existing rule order: `category_overrides.csv`, then the name rules, then the parent chain, then `account_type`. An override row keeps its category. `source = review` still stores the suggested category.

Do not write `current_balance` onto `accounts`.

`nellon_mis` and `nellon_mis_dev` hold the same 357 `category_master` rows. `nellon_mis_test` has the table and no rows. The SQL is the same in all three.

### General ledger

Call `GET /reports/generalledger` with `filter_by=TransactionDate.CustomDate` for one calendar month at a time. Store `debit_total` and `credit_total` on `gl_monthly`, and set `net` to debit minus credit. Replace that month's rows on each fetch. A closed month can be skipped once `synced_at` is set. The current month is fetched again, because Zoho is still posting into it.

The first stored month is January 2026, the start of the financial year. The baseline row `0000-00` is one call from 2000-01-01 through 31 Dec 2025. Prior-year profit and loss then sits entirely in that baseline, and the retained-earnings row can be the sum of baseline `net` for accounts whose `pl_bs` is `PL`.

Do not copy `account_name`, `pl_bs`, or `category` onto `gl_monthly`. A category override then shows on the next report without a reload. Do not write `__prior_years_pl__` into the table.

`tb_monthly` for Apr–Sep 2026 can fill `net` for those six months. Leave `debit` and `credit` empty until a general-ledger call returns them. An empty debit is not a zero. The report can show the net, and it cannot show a debit or credit column for a month that was only seeded.

`GET /journals` does not fill this table. `statement_lines` and `statement_values` are the profit and loss and balance sheet built for one run. Rebuild those from `gl_monthly` and `accounts` when someone opens the report.

### Customers and vendors

Zoho has one contact list. `contact_type=customer` fills `customers`. `contact_type=vendor` fills `vendors`. The primary key is `contact_id`. A customer and a vendor with the same display name are two contacts. Do not merge them, and do not join a document on the name.

The list row is enough for the columns on these tables. Leave `outstanding_receivable_amount` and `outstanding_payable_amount` off the row. `credit_limit` stays, because it is the limit set on the customer, not the amount owed.

Inactive contacts stay. A report can skip them.

Where the loaded invoices stored `customer_id`, seven names still point at more than one id. `CASH CUSTOMER` is `3331482000000342015` and `3331482000186533009`. Run 6 has the name and an empty `customer_id`, so it cannot seed the link. Purchase lines have 103 vendor names and no vendor id. The id has to come from the contact list, not from those lines.

### Items and units

`purchase_rate` and `rate` on `items` are per base unit. A 40 kg bag is not 40 times that rate on the item master.

`stock_on_hand` and `available_stock` are on the current `items` table. Leave them out of the new row. They change on every receipt and invoice.

Resolve a document line's `conversion_rate` from `item_units` by the line's `unit_conversion_id`. When the line has no conversion id, use the `conversion_rate` on the line if Zoho sent one, otherwise 1. When the id is not in `item_units`, store `conversion_rate` 1 and set `flag` to `unknown unit conversion`. `base_quantity` is `quantity × conversion_rate`.

`nellon_mis` and `nellon_mis_dev` hold the same 1,137 items. `nellon_mis_test` has no `items` table.

### Sales money

Keep the Zoho header amounts in the invoice currency. Compute `net_sales` in AED at load time.

`net_sales` on a line is the ex-tax line amount, minus the line discount, minus that line's share of the invoice discount, times `exchange_rate`. Use 1 when the exchange rate is empty. A line's share is its ex-tax amount divided by the sum of the ex-tax amounts.

When `discount_type` is `item_level`, the invoice discount is 0. The line discount is already inside Zoho's line total. When the invoice is tax-inclusive, remove the tax from the line amount before the split, and scale the invoice discount by the same ex-tax ratio. Zoho stored that discount on the tax-inclusive total.

Copy `date` from the invoice onto every line. `flagged_lines` is the count of lines whose `flag` is not empty.

Draft and void invoices are stored. A revenue report skips them. The sync does not delete them.

### COGS

Compute `sales_lines.cogs` at load time. Do not copy `margin_lines.cost_of_sales`, `cost_rate`, or the custom field `cf_line_cogs_document`. The September line document priced packs at the base `purchase_rate` and sits well below the ledger. Store `purchase_price` as Zoho sent it so the choice can be recomputed.

For each line:

1. `purchase_price` is 0. `cogs` is `items.purchase_rate × base_quantity`. That figure is a stand-in. Flag the line.
2. The line names a base unit, `conversion_rate` is greater than 1, and `purchase_price` is in the same range as `items.purchase_rate`. `cogs` is `quantity × conversion_rate × purchase_price`. A pack price is many times the base rate. A band of 25 percent is too tight: Matta sold at 2.754 against a master rate of 2.20.
3. Otherwise `purchase_price` is the pack price. `cogs` is `quantity × purchase_price`. Do not multiply by `conversion_rate`.

`sales_invoices.cogs` is the sum of those line amounts. Do not replace it with `cf_actual_cogs` or with the sum of `cost_of_sales_nellon`. Use those two as checks. An invoice can have two Cost of Sales debit rows, and then the account sum is about twice the custom field.

Checked examples:

| Invoice | What Zoho priced | Ledger | Wrong stored cost |
|---|---|---|---|
| KGT-IN-065645 | 33 bags × 196.0306 per bag | 6,469.01 | 129.03, which is 33 × 3.91 per kg |
| KGT-IN-066783 | 590 bags × 196.0306 per bag | 115,658.05 | 92,276, which is the master rate × 40 |
| KGT-IN-067015 | 110 bags × 50 kg × 3.936359 per kg | 21,649.97 | 22,000, which is 110 × 50 × 4.00 |
| SMR-INV-00570 | 1 bag × 20 kg × 2.754 per kg | 55.08 | 44, which is 1 × 20 × 2.20 |

Multiplying the bag price of KGT-IN-065645 by 40 produces about 258,760, not the ledger. The September cache agrees with `quantity × purchase_price` on most lines. The October cache more often agrees with `quantity × conversion_rate × purchase_price`. The range test above is the rule that fits those samples. It is not yet proved on every multi-line invoice, which is why `purchase_price`, `conversion_rate`, and the item `purchase_rate` all stay on the row.

### Credit notes and debit notes

Load credit notes from `GET /creditnotes` and the detail call. The list row has no lines. A saved list page of 200 is not the full population.

Store `net_sales` and `cogs` as positive numbers. A sales report subtracts the credit note and adds the debit note. Compute the money with the same discount, tax, exchange-rate, and COGS rules as an invoice. The header location is the company location. The line location is the warehouse or van.

The credit-note detail links the source invoice in `invoice_id` and the source line in `invoice_item_id`. `invoices_credited` is the later application of that credit and can name more than one invoice. Do not split `net_sales` across those applications.

A credit-note line can omit `purchase_price`. Use the stand-in `items.purchase_rate × base_quantity` and flag the line. A line with `is_credit_only_item` has no stock movement, so its `cogs` is 0.

Debit notes share `GET /invoices` with sales invoices. List them with `filter_by=Type.DebitNote`. List sales invoices so that this type stays out of `sales_invoices`. The debit note’s own id arrives as `invoice_id`. Store it in `debit_note_id`. The original sale arrives as `reference_invoice_id`. If the same id were written to both tables, revenue would count it twice.

Draft and void notes are stored. A revenue report skips them. Open and closed credit notes both count. A debit note counts when its status is one an invoice report would count.

`inventory_valuation_for_credit_notes` on `cost_of_sales_nellon` is the check for credit-note COGS, not the value to copy. It is a credit, 266,789.30 across 257 documents in the loaded ledger.

`inventory_valuation_for_debit_notes` is not the customer debit note. All 44 ids in the loaded ledger are also `vendor_credit`, and the entry numbers are `KGT-VC-*`. The valuation is a debit and the vendor-credit row is a credit on the same id. Those rows stay on the ledger. Vendor credits still have no document table.

### Purchases

Load bills and purchase orders as two values of `kind`. The current `purchase_lines.amount` is the line total times the exchange rate and does not spread a document-level discount. The new `amount` does. Spread `doc_discount` the same way as `invoice_discount`, and make the line amounts add up to the header `amount`.

On a purchase order, store `quantity`, `quantity_received`, and `quantity_billed`. On a bill, `quantity` is the billed quantity. `purchaseorder_item_id` on a bill line is the `line_item_id` of the purchase-order line.

Draft, void, and cancelled documents are stored. A purchase report skips them.

`purchase_doc_lines` in `nellon_mis_dev` is the old line shape with `fetched_at` and no header table. Do not copy it in as `purchase_docs`.

### Location, salesperson, and van

The invoice header `location_id` is the company location. On all 2,504 cached invoices that is `Koyson General Trading LLC` (`3331482000000095023`). The stock location is `location_id` on the line. The current margin column `van` is that line's location name. Copy the id and the name onto the line. Do not copy the header location into the van.

Do not decide the van by matching the salesperson name to a location name. That match holds for `YOONUS`, `SHINAD`, and `MANSOOR`. It fails for `SHAMEER TAYYIL&HASHIM`, whose lines use `78352-HASHIM AL QUISIS (Warehouse)`, and for the salespersons who share `Koyson General Trading LLC (Warehouse)`.

A `vans` row exists only when `cm_salesperson_profile` assigns a location to a salesperson. The profile also supplies `phone`, `voucher_prefix`, and `cf_cash_account`. The salesperson endpoint does not. A warehouse with no assignment stays in `locations` only.

No database has a location, salesperson, or van table. The cached invoices use 7 line locations and 14 salespersons.

### Do not seed the new cost from the old runs

`nellon_mis_dev.sales_invoices` has 2,500 rows and `sales_lines` has 6,230, migrated from the margin runs for 1 Sep 2026 through 15 Oct 2026. `nellon_mis_test` has one invoice. Those lines have no `line_item_id`, and their `cost_of_sales` is the old calculation. They can seed document identity and sales amounts after the money rules above are applied. They cannot seed `cogs`.
