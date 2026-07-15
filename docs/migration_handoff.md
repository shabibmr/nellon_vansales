# BLoC Migration — Handoff Document

> **Status:** setState migration complete; post-review hardening applied  
> **Date:** 2026-07-15  
> **Verified:** `flutter analyze lib/` → No issues | `flutter test` → **155/155** passed | `setState` grep → 0 real hits. Manual regression (Task 7.3) still open.

---

## What Was Done

The codebase's stated state-management standard is BLoC/Cubit. Prior to this migration, 24 files across the `lib/` tree were still using `setState` for business state. This work migrated every one of them.

### New Classes Created

| Class | Type | Location |
|-------|------|----------|
| `ReportBloc<T>` / `ReportState<T>` / `ReportEvent` | Bloc | `lib/ui/features/reports/bloc/` |
| `ListFilterCubit<T>` | Cubit | `lib/ui/core/cubit/` |
| `GpsCaptureBloc` | Bloc | `lib/ui/core/bloc/` |
| `CreateCustomerCubit` | Cubit | `lib/ui/features/dashboard/cubit/` |
| `DashboardNavCubit` | Cubit | `lib/ui/features/dashboard/cubit/` |
| `DailyStatsCubit` | Cubit | `lib/ui/features/dashboard/cubit/` |
| `ReceiptAllocationBloc` | Bloc | `lib/ui/features/dashboard/bloc/` |
| `MastersSyncBloc` | Bloc | `lib/ui/features/sync/bloc/` |
| `LineEditorCubit` | Cubit | `lib/ui/core/cubit/` |
| `RouteSelectionUiCubit` | Cubit | `lib/ui/features/route/cubit/` |
| `AsyncSearchBloc` / `AsyncSearchState` / `AsyncSearchEvent` | Bloc | `lib/ui/core/bloc/` |
| `SalesReturnDialogCubit` / `SalesReturnDialogState` | Cubit | `lib/ui/features/dashboard/cubit/` |
| `sales_return_dialog_queries.dart` (pure helpers) | — | `lib/ui/features/dashboard/cubit/` |

> **Note:** `invoice_flow_sheet.dart` reuses the existing global `SalesInvoiceBloc` — no new class was needed.

---

## Bugs Fixed In-Flight

The migration surfaced and fixed several pre-existing latent bugs:

| File | Bug | Fix |
|------|-----|-----|
| `receipt_payment_dialog.dart` | No double-tap guard on submit | `submitting` flag in `ReceiptAllocationBloc` |
| `receipt_payment_dialog.dart` | No try/catch around submit | Explicit `failure` state emitted |
| `receipt_payment_dialog.dart` | Live invoice refresh clobbered manual allocations | Option B: preserve manual overrides on refresh |
| `create_customer_dialog.dart` | No try/catch — spinner stuck forever on throw | `CreateCustomerCubit` failure state |
| `masters_sync_page.dart` | Post-loop emit unguarded vs dispose | `isClosed` guard in `MastersSyncBloc` |
| `invoice_flow_sheet.dart` | Local cart leaked across sheet sessions | `ClearCart` dispatched in `initState` |
| `async_search_widget.dart` | 500ms uncancellable delay caused stale-result race | Delay removed; 400ms `Timer` debounce only |
| `invoice_flow_sheet.dart` | Local `_localCart` duplicated `SalesInvoiceBloc` | Removed; drives bloc directly |
| GPS capture | Logic duplicated identically in two files | Unified into `GpsCaptureBloc` |
| `masters_sync_page.dart` | PROCEED read non-listenable `hasCoreMasters` via `watch` (stale after sync) | `hasCoreMasters`/`canProceed` on `MastersSyncState` |
| `invoice_flow_sheet.dart` | Optimistic pop + success before checkout finished | Outcome-driven listener on `successMessage`/`errorMessage` |
| `SalesInvoiceState.copyWith` | `ClearMessages` could not clear null fields (`??` trap) | `clearMessages: true` flag |

---

## Architectural Patterns to Follow

These conventions were established or reinforced throughout the migration. All future features should follow them:

### 1. Side effects in `BlocListener`, rendering in `BlocBuilder`
- Snackbars, `Navigator.pop`, callbacks (e.g. `onPaymentLogged`) → **`BlocListener`**
- Loading spinners, disabled buttons, lists, inline errors → **`BlocBuilder`**

### 2. Always emit fresh collections — never mutate in place
Equatable compares by reference for lists/maps. Mutating a collection in place then emitting the same state instance is a **no-op** — the UI won't rebuild.

```dart
// ❌ Wrong
state.logs.add(line);
emit(state.copyWith(logs: state.logs));

// ✅ Correct
emit(state.copyWith(logs: [...state.logs, line]));
```

### 3. View objects stay widget-local
`TextEditingController`, `FocusNode`, `TabController`, `ScrollController`, debounce `Timer`s — these **never** live inside a Bloc/Cubit. The Bloc holds *values*; the widget owns the view objects and reconciles them via `BlocListener`.

### 4. Use the hybrid stateless/stateful pattern for forms
For dialogs/sheets that need `TextEditingController`s (IME focus), use:
- Outer `StatelessWidget` — provides the `BlocProvider`
- Inner `StatefulWidget` — owns controllers/form keys only, zero business logic

See `item_line_editor_dialog.dart`, `sales_return_dialog.dart`, `async_search_widget.dart` for examples.

### 5. Cache-then-live loading
Pages that paint from Hive then fetch live should seed the bloc's **initial state with cached rows + `isLoading: true`**. Never emit empty+loading first — that regresses the instant-paint UX to a blank spinner.

---

## Test Coverage

| Test file | Covers |
|-----------|--------|
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
| `test/sales_return_dialog_queries_test.dart` | Pure query helpers |
| `test/sales_return_dialog_cubit_test.dart` | `SalesReturnDialogCubit` |

---

## Outstanding Items

### Task 7.3 — Manual Regression Checklist (requires `flutter run`)

These must be verified manually — they cannot be automated:

- [ ] **Reports**: instant cached paint before live arrives; fetch failure keeps data + shows snackbar; date-range + sort after data loads
- [ ] **Receipt**: FIFO recompute while a row is focused (cursor must not jump); double-tap Log Receipt blocked; submit while offline
- [ ] **Masters**: console log streams + caps at 100; PROCEED button enables reactively after bulk sync
- [ ] **GPS**: capture-only mode (fills create-customer fields only) vs persist mode (saves + returns enriched customer); permission-denied path; services-off path
- [ ] **Create customer**: submit throws → spinner must not stick (the fixed latent bug)
- [ ] **Invoice flow** ⚠️ *(highest risk)*:
  - Open sheet → starts **empty** even if invoice editor / order-conversion left items in global cart
  - Increment past van stock → error snackbar appears (via bloc `errorMessage`)
  - Add / decrement / remove / checkout end-to-end
  - Invoice editor page and order-to-invoice conversion still work unaffected
- [ ] **Async search**: rapid typing then clearing; toggle customer↔item mid-search (no stale results)

### Task 5.3 — Invoice flow stock-guard snackbar
The `invoice_flow_sheet.dart` increment path still calls `showErrorSnackBar` directly when `cartQty >= item.stock` rather than listening to `state.errorMessage`. The `AddToCart` / `UpdateCartQuantity` bloc path does emit `errorMessage` on `InsufficientStockException`, but there is no `BlocListener` wired in the sheet to surface it. This is a minor UX gap — the local guard still prevents overcounting, but the stock-limit message from the bloc path would be silently dropped.

**To fix:** add a `BlocListener` in `invoice_flow_sheet.dart` on `state.errorMessage` and call `showErrorSnackBar`.

---

## False Positive (do not touch)

`lib/ui/features/voucher_pdf/bloc/voucher_pdf_bloc.dart` contains the method name `_onResetState` — this is **not** a `setState` call. The grep pattern `setState(` matches the substring inside the method name. This file is a clean `Bloc` and is excluded from scope.
