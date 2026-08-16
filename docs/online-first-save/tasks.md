# Online-first save — Task List

**Source plan:** [plan.md](./plan.md)  
**Status legend:** `[ ]` todo · `[~]` in progress · `[x]` done · `[-]` cancelled

Work top to bottom. Do not switch an editor to `submitOrEnqueue` until Phase 1 persist upserts land.

---

## Phase 1 — Shared submit path

- [x] T1.1 Add `SubmitResult { synced, queued }` and `SyncWorker.submitOrEnqueue`
- [x] T1.2 Offline → enqueue `pending`; online → `_dispatchSync`; fail → enqueue with tag / `retryCount`
- [x] T1.3 Persist-from-payload upserts (replace patch-only `_persist*ZohoId`)
- [x] T1.4 Persist customer into `master_data` on Zoho success (`id` = contact_id)
- [x] T1.5 Persist GPS / contact fields on master only after API success
- [-] T1.6 Cash-closing persist: expense + `cash_closing` on success
- [x] T1.7 In-memory stock pre-check (invoice / return / transfer / convert) before network
- [x] T1.8 `convert_so` payload carries full invoice json; mark order `invoiced` only after success
- [x] T1.9 Expose `submitOrEnqueue` on `SalesRepository` / impl

## Phase 2 — Transaction editors

- [x] T2.1 `sales_invoice_editor_bloc` — drop save-then-enqueue
- [x] T2.2 `sales_invoice_list_bloc` batch convert
- [x] T2.3 `sales_order_editor_bloc` (create + update)
- [x] T2.4 `receipt_editor_bloc` + `receipt_allocation_bloc`
- [x] T2.5 `sales_return_editor_bloc` + `sales_return_dialog_cubit`
- [x] T2.6 `expense_editor_bloc` + `expense_log_cubit`
- [x] T2.7 `stock_transfer_bloc`
- [x] T2.8 Toast `Saved` vs `Saved to upload queue`

## Phase 3 — Customer / GPS / cash closing

- [x] T3.1 `create_customer_cubit` — no master write until Zoho success
- [x] T3.2 `gps_capture_bloc` — remove local-first + direct PUT
- [x] T3.3 `customer_missing_fields_dialog` — same as T3.2
- [-] T3.4 `cash_closing_cubit`
- [x] T3.5 Guards: no docs for `temp_` customers; convert only if `zohoOrderId` set

## Phase 4 — Tests and verify

- [x] T4.1 `sync_id_resolution_test` — persist inserts, not patches
- [x] T4.2 `sales_repository_enqueue_test` → submitOrEnqueue cases
- [x] T4.3 Editor/cubit tests: success / fail / retry (invoice, order, receipt, return, expense, stock, customer, gps; cash closing skipped)
- [x] T4.4 Success: history/master has zoho id, queue empty, stock moved
- [x] T4.5 Fail: queue only, history/master/stock unchanged
- [x] T4.6 `flutter analyze` + targeted `flutter test`
