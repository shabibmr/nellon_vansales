# Last-modified sync — endpoint check

Checked 2026-10-21 against the local Zoho Books v3 OpenAPI files in `zohodocs/`. No live Zoho call was made.

Task: scripts that sync each dataset from the newest stored `last_modified_time`. A list can do that only when `GET` accepts `last_modified_time` as a query parameter. A timestamp on the response is not a filter.

Base: `https://www.zohoapis.com/books/v3`. Pass `organization_id` on every call. Timestamp examples in the specs look like `2013-11-18T02:02:51-0800` (offset, no colon).

## Result

Five of the ten have a Books list filter on `last_modified_time`. Five do not.

Transaction journals are `gl_journals`: every ledger posting from Books `GET /chartofaccounts/transactions`. That is not `GET /journals` (manual journal vouchers only).

| # | Dataset | List endpoint | `last_modified_time` filter | Response has the field |
|---|---|---|---|---|
| 1 | Sales | `GET /invoices` | Yes. Modified **after** the timestamp. | Yes |
| 2 | Purchase | `GET /bills` | Yes. Modified **at or after** the timestamp. | Yes |
| 3 | Sales return | `GET /creditnotes` | **No** | Yes, on the list row |
| 4 | Purchase return | `GET /vendorcredits` | Yes | Yes |
| 5 | Transaction journals (`gl_journals`) | `GET /chartofaccounts/transactions` | **No** | **No.** Rows have `transaction_date`, not `last_modified_time`. |
| 6 | Sales orders | `GET /salesorders` | Yes | Yes |
| 7 | Purchase orders | `GET /purchaseorders` | Yes | Yes |
| 8 | Items | `GET /items` | **No** on Books | Returned by the live list (see note). Books OpenAPI omits the field. |
| 9 | Vendors | `GET /contacts?contact_type=vendor` | **No** | Yes |
| 10 | Customers | `GET /contacts?contact_type=customer` | **No** | Yes |

Detail calls (lines, amounts) stay `GET /{resource}/{id}` after the list. The filter is only on the list.

`proposal/Sync_Logic.md` tells the sync to pass `last_modified_time` on `GET /contacts` and `GET /items`. The Books list specs do not define that parameter. Do not treat those two calls as delta filters until a live probe says otherwise.

## One by one

### 1. Sales — filter yes

- List: `GET /invoices`
- Spec: `zohodocs/invoices.yml`
- Filter: `last_modified_time`. "Search invoices modified after a specific time." Example `2013-11-18T02:02:51-0800`.
- Document date, which is not the modified time: `date`, `date_start`, `date_end`, `date_before`, `date_after`.
- Detail: `GET /invoices/{invoice_id}`

### 2. Purchase (bills) — filter yes

- List: `GET /bills`
- Spec: `zohodocs/bills.yml`
- Filter: `last_modified_time`. "bills modified at or after a specific time." Example `2013-09-11T17:18:32+0530`.
- Document date: `date`, plus `date_start` / `date_end` / `date_before` / `date_after` as variants of `date`.
- Detail: `GET /bills/{bill_id}`

### 3. Sales return (credit notes) — filter no

- List: `GET /creditnotes`
- Spec: `zohodocs/credit-notes.yml`
- List query has `date` (the date the credit note was raised, `yyyy-mm-dd`), status, customer, item, `search_text`, sort, page. There is no `last_modified_time` parameter.
- The list object still returns `last_modified_time` (example `2016-06-05T02:30:08-0700`) and `created_time`. A change on an old credit note is visible only by reading the list (or a document-date window) and comparing the field locally.
- Sort columns: `customer_name`, `creditnote_number`, `balance`, `total`, `date`, `created_time`. `last_modified_time` is not a sort column.
- Detail: `GET /creditnotes/{creditnote_id}`

### 4. Purchase return (vendor credits) — filter yes

- List: `GET /vendorcredits`
- Spec: `zohodocs/vendor-credits.yml`
- Filter: `last_modified_time`. "Filter vendor credits by last modified time." Example `2014-08-28T22:53:31-0700`. The text does not say "after" versus "equal".
- Document date: `date`, with `date_start`, `date_end`, `date_before`, `date_after`.
- Sort may use `last_modified_time`.
- Detail: `GET /vendorcredits/{vendor_credit_id}`
- Customer debit notes are a different document (`GET /invoices` with the debit-note filter in `zohodocs/customer-debit-notes.yml`). That list does have `last_modified_time`. They are not purchase returns.

### 5. Transaction journals (`gl_journals`) — filter no

- List: `GET /chartofaccounts/transactions`
- Spec: `zohodocs/chart-of-accounts.yml` (`list_chart_of_account_transactions`)
- One Books call per ledger account. `account_id` is required.
- There is **no** `last_modified_time` query parameter, and the transaction object in the spec has no `last_modified_time` or `created_time`. The local `gl_journals` table also has no `last_modified_time` column. It stores `transaction_date` and `fetched_at`.
- The only date window is the transaction date: `date`, with variants `date.start`, `date.end`, `date.before`, and `date.after`. Format `yyyy-mm-dd`.
- Other query params: `amount` (and less/greater variants), `transaction_type`, `filter_by`, `sort_column`, `page`, `per_page`.
- A posting changed after its transaction date is missed unless that date window is listed again. Deletes are missed unless the window is re-read and rows that disappeared are removed. Primary key is `(account_id, categorized_transaction_id)`.
- `GET /journals` is a different Books resource (manual journal vouchers). It is not the source for `gl_journals`.

`GET /reports/generalledger` is also not a substitute.

- It is a Books report, not a posting list. There is no `last_modified_time` parameter.
- The date window is the transaction date: `filter_by=TransactionDate.CustomDate` plus `from_date` and `to_date` (`yyyy-mm-dd`). Without `filter_by`, those dates are ignored.
- A saved pull for 2026-04-01 to 2026-10-19 (`output/preflight_generalledger_2026-04-01_2026-10-19.json`) has 358 rows. Each row is one account: `account_id`, `account_code`, `name`, `debit_total`, `credit_total`, `balance`, `is_debit`. `values[]` repeats those three totals. There is no posting id, document number, or modified time.
- It can show which accounts moved in a date range. It cannot fill `gl_journals`. The posting row remains `GET /chartofaccounts/transactions`.

## Published `/reports/` and `/transactions/` paths

Checked against the live Books v3 docs index on 2026-10-21 ([API docs](https://www.zoho.com/books/api/v3/journals/)). No Zoho call was made. The index has no Reports module and no `reports.yml`. Financial statements are not in that published list.

Paths the docs actually publish under `/reports/` are workflow logs only, on the [Workflows](https://www.zoho.com/books/api/v3/workflows/) page:

| Method and path | What it returns |
|---|---|
| `GET /reports/workflowlogs` | Workflow execution history |
| `GET /reports/upcomingworkflows` | Time-based workflows waiting to run |
| `GET /reports/upcomingactions` | Time-based workflow actions waiting to run |
| `GET /reports/failedworkflows` | Failed workflow runs |
| `GET /reports/failedworkflowactions` | Failed workflow actions |

The only published path under `/transactions/` is on the Journals page:

`GET /transactions/{transaction_id}/journals`

- Required query: `entity_type`. Published values include `journal`, `invoice`, `creditnote`, `expense`, `bill`, `vendor_credit`, `customer_payment`, `vendor_payment`, and the docs say "and more".
- Optional: `report_basis` = `cash` or `accrual`.
- Returns the journal lines of that one document. The sample body includes `last_modified_time`. It is not a list of every posting, and it cannot be filtered by a modified-time watermark.

The account posting list that is published, and is not under those two prefixes, is `GET /registers/{account_id}/transactions` ([Registers](https://www.zoho.com/books/api/v3/registers/), OpenAPI `registers.yml`). Date filter is `filter_by=TransactionDate.CustomDate` with `from_date` and `to_date`. There is no `last_modified_time` parameter on any Registers path. Response rows shown are `transaction_id`, `transaction_date`, `transaction_type`, `account_id`, `debit_amount`, and `credit_amount`.

The Registers module has seven calls. Every path still needs one `{account_id}`. The transaction list also accepts a query `account_id` of up to 50 comma-separated ids.

| Call | Use |
|---|---|
| `GET /registers/{account_id}/transactions` | Postings for that account. Date presets or `TransactionDate.CustomDate` plus `from_date` / `to_date`. Also `cash_based`, `sort_column` (`date`, `transaction_type`, `account_type`, `account_name`, `account_code`), `optional_columns` (`account_code`, `running_balance`, `net_amount`), `show_fcy`, `group_by`, `page`, `per_page` (default 10). |
| `GET /registers/{account_id}/bulkhistory` | History of bulk updates and deletes on that register. Sort is `created_time` only. |
| `GET /registers/{account_id}/bulkhistory/{comment_id}` | One bulk action, plus the transactions it touched (`entity_id`, `transaction_number`, `transaction_type`, `entity_status`). |
| `GET /registers/{account_id}/bulkupdate/editpage` | Field metadata for a bulk update (`fields[]`: `field`, `label`, `data_type`). |
| `GET /registers/{account_id}/budgetvsactuals` | Budget versus actual for that account. Optional `budget_id`, same transaction-date window, `period` = `monthly`, `quarterly`, `half-yearly`, or `yearly`. |
| `PUT /registers/{account_id}/transactions/bulkupdate` | Writes. Changes selected transactions. |
| `PUT /registers/{account_id}/transactions/bulkdelete` | Writes. Deletes selected transactions. |

### 6. Sales orders — filter yes

- List: `GET /salesorders`
- Spec: `zohodocs/sales-order.yml`
- Filter: `last_modified_time`. "Last Modified time of the Sales Order." Example `2014-08-25T11:23:26+0530`. "After" is not stated.
- `sort_column` may be `last_modified_time`.
- Document date: `date`, `date_start`, `date_end`, `date_before`, `date_after`.
- Detail: `GET /salesorders/{salesorder_id}`

### 7. Purchase orders — filter yes

- List: `GET /purchaseorders`
- Spec: `zohodocs/purchase-order.yml`
- Filter: `last_modified_time`. "Search purchase order by last modified time." Example `2014-02-10T15:26:26+0530`.
- Document date: `date`, `date_start`, `date_end`, `date_before`, `date_after`.
- Sort columns do not include `last_modified_time` (`vendor_name`, `purchaseorder_number`, `date`, `delivery_date`, `total`, `created_time`).
- Detail: `GET /purchaseorders/{purchaseorder_id}`

### 8. Items — filter no on Books

- List: `GET /items`
- Spec: `zohodocs/items.yml` (Books). Sort is only `name`, `rate`, `tax_name`. Filters are name, description, rate, tax, account, `Status.All|Active|Inactive`, search, page. No `last_modified_time` and no created-date parameter.
- The Books OpenAPI file also never mentions `last_modified_time` as a response field. `fetch_items.py` still reads `created_time` and `last_modified_time` off each Books list row, so the live list has been returning the timestamp. That supports a local compare after a full list. It does not add a server filter.
- Unit conversions are not on the list. They need `GET /items/{item_id}`.
- Zoho Inventory `zohodocs/inventory/items.yml` does define `last_modified_time` ("modified after the given date and time"). That API is outside the Books license used for these reports. Do not point the sync at it.

### 9. Vendors — filter no

- List: `GET /contacts?contact_type=vendor`
- Spec: `zohodocs/contacts.yml`
- No `last_modified_time` query parameter. `sort_column=last_modified_time` is allowed, together with `created_time`. Sorting is not a delta filter: paging still walks the whole set, and a row can move between pages while you read them.
- Each contact returns `last_modified_time` (example `2013-10-07T18:24:51+0530`).
- `filter_by` is status (`Status.All`, `Status.Active`, `Status.Inactive`, and others). No modified-date preset.
- Detail: `GET /contacts/{contact_id}`

### 10. Customers — filter no

- Same list and same gap as vendors: `GET /contacts?contact_type=customer`.
- Keep the two contact types apart. The same display name can exist once as a customer and once as a vendor.

## What a later script can do

Safe incremental list (pass the newest stored timestamp):

1. Sales — `GET /invoices?last_modified_time=`
2. Purchase — `GET /bills?last_modified_time=`
3. Purchase return — `GET /vendorcredits?last_modified_time=`
4. Sales orders — `GET /salesorders?last_modified_time=`
5. Purchase orders — `GET /purchaseorders?last_modified_time=`

Needs another strategy:

- Sales return — full `GET /creditnotes` pages, or a document-date window, then skip rows whose `last_modified_time` is unchanged. An edit to an old note is outside a date window.
- Transaction journals — `GET /chartofaccounts/transactions` once per account, windowed by `date.start` and `date.end`. There is no modified-time column to skip on.
- Items, vendors, customers — full list, then skip unchanged `last_modified_time`. Books does not offer the query parameter.

None of these lists report deletes. A row removed in Zoho stays in MariaDB until that id is dropped by a full reconcile.

Invoice "after" and bill "at or after" are the only two specs that state the comparison. For the others, overlap the watermark by one timestamp or re-read the boundary row so an equal timestamp is not skipped.
