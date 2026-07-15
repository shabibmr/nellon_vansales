# BLoC Migration Status Dashboard

This dashboard tracks the progress of migrating all 24+ `setState` files to Bloc/Cubit-driven state, along with fixing duplicate logic (GPS capture, local cart) and scope gaps.

**Current progress:** 24 / 24 target files migrated (setState removed). Post-review hardening applied for masters PROCEED reactivity and invoice checkout outcomes. Full suite should be re-run after those fixes. Manual regression (Task 7.3) still open.

## 📋 General Decisions & Configuration
- **Scope Gap (`sales_return_dialog.dart`)**: **Resolved** — migrated to `SalesReturnDialogCubit` in Phase 6.
- **Receipt Payment Live Refresh**: **Option B** selected. Manual allocation overrides will be preserved when a live open-invoices refresh completes.

---

## 🚀 Migration Phases & Tasks

### Phase 0 — Foundations & Decisions
- [x] Task 0.1 — Baseline & tooling (confirmed 24 files + 1 gap + 1 false positive)
- [x] Task 0.2 — Conventions lock-in (states use Equatable; page-scoped providers)
- [x] Task 0.3 — `SortableReportScaffold` capability check (fully Stateless)
- [x] Task 0.4 — Scope gap decision (resolved: migrate `sales_return_dialog.dart`)

### Phase 1 — Group A: Reports (13 pages, 1 generic `ReportBloc`)
- [x] Task 1.1 — Design `ReportState<T>`, `ReportEvent`, `ReportBloc<T>`
- [x] Task 1.2 — Unit tests for `ReportBloc<T>`
- [x] Task 1.3 — Migrate standard invoice-aggregate reports (item sales, customer value, expense, etc.)
- [x] Task 1.4 — Variant: `stock_report_page.dart` (location context, live data status)
- [x] Task 1.5 — Variant: `order_status_report_page.dart` (OrderStatusFilter)
- [x] Task 1.6 — Multi-list: `aging_receivables_report_page.dart` (open invoices + customer names map)
- [x] Task 1.7 — Multi-list: `transactions_summary_report_page.dart` (parallel wait on 4 lists)
- [x] Task 1.8 — Group A verification (analyze, test, manual)

### Phase 2 — Shared primitives (Group E core & Group F)
- [x] Task 2.1 — Implement generic `ListFilterCubit<T>`
- [x] Task 2.2 — Implement unified `GpsCaptureBloc` (persist vs capture-only modes)
- [x] Task 2.3 — Wire GPS & filter cubit into `customer_selector_sheet.dart`
- [x] Task 2.4 — Wire GPS into `create_customer_dialog.dart` (capture-only mode)
- [x] Task 2.5 — Wire filter cubit into `item_search_sheet.dart`
- [x] Task 2.6 — Phase 2 verification

### Phase 3 — Group E Remainder: `CreateCustomerCubit`
- [x] Task 3.1 — Design `CreateCustomerCubit` (temp customer creation, fallback active route check, Zoho queueing)
- [x] Task 3.2 — Integrate `CreateCustomerCubit` into `create_customer_dialog.dart`
- [x] Task 3.3 — Phase 3 verification

### Phase 4 — Independent Groups (B, C, D, G, H, J)
- [x] **Group B (Dashboard)**
  - [x] Task 4.B.1 — `DashboardNavCubit`
  - [x] Task 4.B.2 — `DailyStatsCubit` (loads & refreshes today's sales/payments/expenses/returns/deliveries)
  - [x] Task 4.B.3 — Convert dashboard shell (tab index + stats refresh callbacks)
  - [x] Task 4.B.4 — Group B verification
- [x] **Group C (Receipt Payment)**
  - [x] Task 4.C.1 — Model events & state (`ReceiptAllocationBloc`)
  - [x] Task 4.C.2 — Implement FIFO allocation logic and manual override triggers
  - [x] Task 4.C.3 — Cache-then-live integration (Option B: manual overrides preserved)
  - [x] Task 4.C.4 — Submit path with double-tap guard and try/catch error safety
  - [x] Task 4.C.5 — Widget controllers focus-aware reconciliation
  - [x] Task 4.C.6 — Receipt unit tests
  - [x] Task 4.C.7 — Group C verification
- [x] **Group D (Masters Sync)**
  - [x] Task 4.D.1 — Model events & state (`MastersSyncBloc`)
  - [x] Task 4.D.2 — Implement log appender (cap at 100), sync one, sync all progressive handlers
  - [x] Task 4.D.3 — Widget auto-scroll + PROCEED button enable condition
  - [x] Task 4.D.4 — Masters sync unit tests
  - [x] Task 4.D.5 — Group D verification
- [x] **Group G (Item Line Editor)**
  - [x] Task 4.G.1 — Design `LineEditorCubit` (quantity, rate, discount, subtotal, tax, total)
  - [x] Task 4.G.2 — Wire cubit to `item_line_editor_dialog.dart`
  - [x] Task 4.G.3 — Group G verification
- [x] **Group H (Route Page)**
  - [x] Task 4.H.1 — Design `RouteSelectionUiCubit`
  - [x] Task 4.H.2 — Wire cubit to `route_page.dart`
  - [x] Task 4.H.3 — Group H verification
- [x] **Group J (Async Search)**
  - [x] Task 4.J.1 — Design `AsyncSearchBloc` (in-memory customer/item search)
  - [x] Task 4.J.2 — Debounce keystrokes (400ms Timer) and drop 500ms artificial delay to avoid race condition
  - [x] Task 4.J.3 — Wire bloc to `async_search_widget.dart`
  - [x] Task 4.J.4 — Async search unit tests
  - [x] Task 4.J.5 — Group J verification

### Phase 5 — Group I: Invoice Flow & existing `SalesInvoiceBloc` (High Risk)
- [x] Task 5.1 — Remove local cart maps; bind UI to `SalesInvoiceState.cart`
- [x] Task 5.2 — Dispatch `ClearCart` on sheet open (`initState`) to clear stale global cart state
- [x] Task 5.3 — Wire stock-guard feedback via `state.errorMessage` → snackbar (`BlocListener` + `ClearMessages`)
- [x] Task 5.4 — Wire search filter via shared `ListFilterCubit<Item>`
- [x] Task 5.5 — Checkout outcome-driven: pop/snackbar/`onInvoiceSubmitted` only on `successMessage`; button disabled while `isLoading`
- [ ] Task 5.6 — Verify invoice editor and order-to-invoice conversion flows remain unaffected (manual)
- [x] Task 5.7 — Unit tests for ClearCart, stock reject, checkout success/fail, double-submit guard (`test/invoice_flow_cart_test.dart`)
- [ ] Task 5.8 — Group I full verification (manual regression)

### Phase 6 — Group Gap: `SalesReturnDialogCubit`
- [x] Task 6.1 — Design `SalesReturnDialogCubit` (manages item selection, matching invoices, allocation quantities, submit)
- [x] Task 6.2 — Integrate cubit into `sales_return_dialog.dart`
- [x] Task 6.3 — Phase 6 verification

### Phase 7 — Final Verification & Cleanup
- [x] Task 7.1 — Re-run full static analysis + full test suite after post-review fixes → `flutter analyze lib/` clean; `flutter test` **155/155** passed
- [x] Task 7.2 — Confirm zero setState occurrences under `lib/` — **verified**; only `voucher_pdf_bloc.dart:_onResetState` substring (not a real call) remains
- [ ] Task 7.3 — Execute manual regression script checklist (manual `flutter run` required — see `bloc_migration_plan.md` §Verification)
- [x] Task 7.4 — Code cleanup, documentation, and handoff — see `migration_handoff.md`

### Post-review hardening (2026-07-15)
- [x] Masters: `hasCoreMasters` / `canProceed` on `MastersSyncState`; PROCEED reads bloc state only
- [x] Masters: recompute after SyncOne/SyncAll; `isClosed` guards; LoadRoutes on sync completion via listener
- [x] Invoice: outcome-driven checkout; `ClearMessages` actually clears; double-submit guard
- [x] Invoice search uses `ListFilterCubit`
- [x] Stock report uses shared `ReportBlocHost` (includes error snackbar)
- [x] Create-customer GPS denial uses error snackbar (not success)

---

## 🏷️ New Classes Inventory

| Class | Type | Path | Status |
|---|---|---|---|
| `ReportBloc<T>` / `ReportState<T>` / `ReportEvent` | Bloc | `lib/ui/features/reports/bloc/` | [x] Done |
| `ListFilterCubit<T>` | Cubit | `lib/ui/core/cubit/` | [x] Done |
| `GpsCaptureBloc` | Bloc | `lib/ui/core/bloc/` | [x] Done |
| `CreateCustomerCubit` | Cubit | `lib/ui/features/dashboard/cubit/` | [x] Done |
| `DashboardNavCubit` | Cubit | `lib/ui/features/dashboard/cubit/` | [x] Done |
| `DailyStatsCubit` | Cubit | `lib/ui/features/dashboard/cubit/` | [x] Done |
| `ReceiptAllocationBloc` | Bloc | `lib/ui/features/dashboard/bloc/` | [x] Done |
| `MastersSyncBloc` | Bloc | `lib/ui/features/sync/bloc/` | [x] Done |
| `LineEditorCubit` | Cubit | `lib/ui/core/cubit/` | [x] Done |
| `RouteSelectionUiCubit` | Cubit | `lib/ui/features/route/cubit/` | [x] Done |
| `AsyncSearchBloc` / `AsyncSearchState` / `AsyncSearchEvent` | Bloc | `lib/ui/core/bloc/` | [x] Done |
| `SalesReturnDialogCubit` / `SalesReturnDialogState` | Cubit | `lib/ui/features/dashboard/cubit/` | [x] Done |
| `sales_return_dialog_queries.dart` (pure helpers) | — | `lib/ui/features/dashboard/cubit/` | [x] Done |

---

## 🧪 Migration Test Coverage

| Test file | Covers |
|---|---|
| `test/report_bloc_test.dart` | `ReportBloc<T>` |
| `test/list_filter_cubit_test.dart` | `ListFilterCubit<T>` |
| `test/gps_capture_bloc_test.dart` | `GpsCaptureBloc` |
| `test/create_customer_cubit_test.dart` | `CreateCustomerCubit` |
| `test/dashboard_cubits_test.dart` | `DashboardNavCubit`, `DailyStatsCubit` |
| `test/receipt_allocation_bloc_test.dart` | `ReceiptAllocationBloc` |
| `test/masters_sync_bloc_test.dart` | `MastersSyncBloc` |
| `test/line_editor_cubit_test.dart` | `LineEditorCubit` |
| `test/route_selection_ui_cubit_test.dart` | `RouteSelectionUiCubit` |
| `test/async_search_bloc_test.dart` | `AsyncSearchBloc` |
| `test/sales_return_dialog_queries_test.dart` | Eligible items / matching invoices helpers |
| `test/sales_return_dialog_cubit_test.dart` | `SalesReturnDialogCubit` |
| `test/invoice_flow_cart_test.dart` | `SalesInvoiceBloc` cart / checkout (invoice flow) |

---

## 🗂️ Files Inventory

### Reports (Group A)
- [x] `lib/ui/features/reports/views/item_sales_report_page.dart`
- [x] `lib/ui/features/reports/views/aging_receivables_report_page.dart`
- [x] `lib/ui/features/reports/views/stock_report_page.dart`
- [x] `lib/ui/features/reports/views/order_status_report_page.dart`
- [x] `lib/ui/features/reports/views/customerwise_returns_summary_report_page.dart`
- [x] `lib/ui/features/reports/views/itemwise_returns_summary_report_page.dart`
- [x] `lib/ui/features/reports/views/orders_summary_by_customer_report_page.dart`
- [x] `lib/ui/features/reports/views/itemwise_orders_summary_report_page.dart`
- [x] `lib/ui/features/reports/views/sales_summary_by_customer_item_report_page.dart`
- [x] `lib/ui/features/reports/views/sales_summary_by_customer_value_report_page.dart`
- [x] `lib/ui/features/reports/views/invoice_receipts_summary_report_page.dart`
- [x] `lib/ui/features/reports/views/expense_summary_report_page.dart`
- [x] `lib/ui/features/reports/views/transactions_summary_report_page.dart`

### Core Primitives & Widgets
- [x] `lib/ui/core/widgets/async_search_widget.dart`
- [x] `lib/ui/core/widgets/customer_selector_sheet.dart`
- [x] `lib/ui/core/widgets/item_search_sheet.dart`
- [x] `lib/ui/core/widgets/item_line_editor_dialog.dart`

### Features Dashboard
- [x] `lib/ui/features/dashboard/views/dashboard_page.dart`
- [x] `lib/ui/features/dashboard/widgets/create_customer_dialog.dart`
- [x] `lib/ui/features/dashboard/widgets/invoice_flow_sheet.dart`
- [x] `lib/ui/features/dashboard/widgets/receipt_payment_dialog.dart`
- [x] `lib/ui/features/dashboard/widgets/sales_return_dialog.dart`

### Features Route
- [x] `lib/ui/features/route/views/route_page.dart`

### Features Sync
- [x] `lib/ui/features/sync/views/masters_sync_page.dart`
