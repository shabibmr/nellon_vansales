# Online-first save (queue only on Zoho failure)

**Tasks:** [tasks.md](./tasks.md)

## Goal

`local_history_box` and `master_data_box` hold only Zoho-confirmed rows. Save tries Zoho immediately; the queue is a retry inbox, not a second copy of the document.

Locked product rules:

- Pending work appears on the **Upload Queue tab only** (not invoice/order/receipt/… lists).
- **No van-stock change** and **no follow-on docs** until Zoho succeeds.

## Current vs new

```
TODAY                         NEW
Save                          Save
  → local_history (pending)     → POST/PUT Zoho
  → sync_queue                    ├ success → local (zoho id) + stock
  → later Zoho                    └ fail    → sync_queue only
  → patch zoho id                   SyncWorker retries
                                    ├ success → local + stock
                                    └ fail    → retryCount++
```

## Shared API

Add `SyncWorker.submitOrEnqueue(SyncQueueItem item) → SubmitResult { synced, queued }`.

1. Build payload as today (`Model.toJson()`). Do **not** write history/master.
2. Pre-validate van stock in memory (invoice / return / transfer / convert). Throw before any network call.
3. If offline → enqueue `pending`, return `queued`.
4. If online → `_dispatchSync(item)` (same as the worker).
   - Success → persist from payload + Zoho id, return `synced`.
   - Failure → enqueue with `errorMessage` + category tag; `pending` if transient, `failed` + `[Needs Attention]` if permanent. Return `queued`.
5. Editors stop calling `saveLocal*` then `enqueue*`. They call `submitOrEnqueue` and toast `Saved` vs `Saved to upload queue`.

`SalesRepository` exposes this once; all 11 send types go through it (invoice, sales_order, update_sales_order, convert_so, receipt, return, expense, stock_transfer, customer, customer_gps_update, customer_contact_update).

## Persist on Zoho success (upsert, not patch)

Today `_persist*ZohoId` only patches a row that already exists. That becomes a no-op. Change each helper to **insert from the queue payload**:

| Type | Write target | Id / flags | Side effects |
|---|---|---|---|
| invoice / convert_so | `local_history` invoices | `id` + `zohoInvoiceId` = Zoho id, `isPendingSync: false` | `saveLocalInvoice` (deduct stock) |
| sales_order | orders | `zohoOrderId` set, pending false | none |
| update_sales_order | replace existing order | pending false | none (history kept the old synced version until now) |
| receipt / expense | receipts / expenses | zoho id set | none |
| return | returns | zoho id set | `saveLocalReturn` (restore stock) |
| stock_transfer | transfers | zoho id set | `saveLocalStockTransfer` (apply stock) |
| customer | `master_data` customers | `id` = Zoho `contact_id`, pending false | insert; no temp_ row |
| gps / contact | master customer | — | apply fields only after API success |
| cash closing | cash_closing + expense | pending false | persist both when the queued `expense` succeeds |

`convert_so` payload must carry the **full invoice json** plus `salesorder_id`. Do **not** mark the order `invoiced` until convert succeeds.

Customer create: drop `saveCustomers` before enqueue. On success insert with Zoho id. GPS/contact: drop the local-first + optional direct PUT; use `submitOrEnqueue` only.

Keep temp-id rewrite on the queue for grandfathered items. New data will not create follow-ons against queued parents (they are not in lists / master).

## Call-site changes (remove save-then-enqueue)

- `sales_invoice_editor_bloc`, `sales_invoice_list_bloc` (batch convert)
- `sales_order_editor_bloc`
- `receipt_editor_bloc`, `receipt_allocation_bloc`
- `sales_return_editor_bloc`, `sales_return_dialog_cubit`
- `expense_editor_bloc`, `expense_log_cubit`
- `stock_transfer_bloc`
- `cash_closing_cubit`
- `create_customer_cubit`
- `gps_capture_bloc`, `customer_missing_fields_dialog`

Defensive guards (lists already hide queued docs):

- No invoice/order/receipt/return for `temp_` customers.
- Convert only if `order.zohoOrderId` is set and no open `convert_so` for that order.

## What we do not change

- `ZohoPayloadMapper` still shapes payload at POST time.
- Queue ordering (customers → invoices/orders → rest) and backoff / `retryCount`.
- Document numbers still allocated locally (`ignore_auto_number_generation`).
- Existing `isPendingSync` history rows: **grandfather** — they drain on the old path. New saves never write pending history.

## Tests

Rewrite editor/cubit tests from “saveLocal then enqueue” to:

1. Zoho ok → history/master written with zoho id, queue empty, stock moved.
2. Zoho/offline fail → queue has item, history/master unchanged, stock unchanged.
3. Worker retry success → same persist as (1), `retryCount` path on fail.

Touch: `sync_id_resolution_test`, `sales_repository_enqueue_test`, invoice/order/receipt/return/expense/stock/customer/gps/cash_closing editor tests.

## Implementation order

1. `submitOrEnqueue` + persist-from-payload upserts + stock pre-check.
2. Switch all save call sites; convert_so full invoice payload.
3. Customer + GPS/contact + cash closing.
4. Tests + `flutter analyze` / targeted `flutter test`.
