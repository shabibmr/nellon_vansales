# Online-first save — Task List

**Source plan:** [plan.md](./plan.md)  
**Status legend:** `[ ]` todo · `[~]` in progress · `[x]` done · `[-]` cancelled

Work top to bottom. Do not switch an editor to `submitOrEnqueue` until Phase 1 persist upserts land.

---

## Phase 1 — Shared submit path

- [ ] T1.1 Add `SubmitResult { synced, queued }` and `SyncWorker.submitOrEnqueue`
- [ ] T1.2 Offline → enqueue `pending`; online → `_dispatchSync`; fail → enqueue with tag / `retryCount`
- [ ] T1.3 Persist-from-payload upserts (replace patch-only `_persist*ZohoId`)
- [ ] T1.4 Persist customer into `master_data` on Zoho success (`id` = contact_id)
- [ ] T1.5 Persist GPS / contact fields on master only after API success
- [ ] T1.6 Cash-closing persist: expense + `cash_closing` on success
- [ ] T1.7 In-memory stock pre-check (invoice / return / transfer / convert) before network
- [ ] T1.8 `convert_so` payload carries full invoice json; mark order `invoiced` only after success
- [ ] T1.9 Expose `submitOrEnqueue` on `SalesRepository` / impl

## Phase 2 — Transaction editors

- [ ] T2.1 `sales_invoice_editor_bloc` — drop save-then-enqueue
- [ ] T2.2 `sales_invoice_list_bloc` batch convert
- [ ] T2.3 `sales_order_editor_bloc` (create + update)
- [ ] T2.4 `receipt_editor_bloc` + `receipt_allocation_bloc`
- [ ] T2.5 `sales_return_editor_bloc` + `sales_return_dialog_cubit`
- [ ] T2.6 `expense_editor_bloc` + `expense_log_cubit`
- [ ] T2.7 `stock_transfer_bloc`
- [ ] T2.8 Toast `Saved` vs `Saved to upload queue`

## Phase 3 — Customer / GPS / cash closing

- [ ] T3.1 `create_customer_cubit` — no master write until Zoho success
- [ ] T3.2 `gps_capture_bloc` — remove local-first + direct PUT
- [ ] T3.3 `customer_missing_fields_dialog` — same as T3.2
- [ ] T3.4 `cash_closing_cubit`
- [ ] T3.5 Guards: no docs for `temp_` customers; convert only if `zohoOrderId` set

## Phase 4 — Tests and verify

- [ ] T4.1 `sync_id_resolution_test` — persist inserts, not patches
- [ ] T4.2 `sales_repository_enqueue_test` → submitOrEnqueue cases
- [ ] T4.3 Editor/cubit tests: success / fail / retry (invoice, order, receipt, return, expense, stock, customer, gps, cash closing)
- [ ] T4.4 Success: history/master has zoho id, queue empty, stock moved
- [ ] T4.5 Fail: queue only, history/master/stock unchanged
- [ ] T4.6 `flutter analyze` + targeted `flutter test`
