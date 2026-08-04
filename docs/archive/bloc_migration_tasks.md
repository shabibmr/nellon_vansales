# BLoC Migration — Detailed Task Breakdown

Source plan: [`docs/bloc_migration_plan.md`](bloc_migration_plan.md)

**Goal:** Replace every real `setState(` usage under `lib/` with Bloc/Cubit-driven state. No cosmetic exceptions. Fix the two structural duplications (GPS capture, invoice-flow local cart) in the same pass.

**Inventory (plan baseline):** 24 files → 11 new classes (5 Bloc, 6 Cubit) + 1 existing-Bloc reuse (`SalesInvoiceBloc`).

**False positive (out of scope):** `lib/ui/features/voucher_pdf/bloc/voucher_pdf_bloc.dart` — match is `_onResetState(`, not `setState(`.

**Discovered gap (now designed for INCLUDE):** `lib/ui/features/dashboard/widgets/sales_return_dialog.dart` — migrate via **`SalesReturnQuickCubit`**. Full design: [`docs/sales_return_dialog_design.md`](sales_return_dialog_design.md). See [Task 0.4](#task-04--scope-gap-sales_return_dialogdart--include-design-locked).

---

## How to use this file

- Tasks are ordered by recommended execution (matches plan § Execution order).
- Each task has: **Do**, **Edge cases**, **Acceptance**, **Verify**.
- Check boxes as you complete work.
- After every group: run `flutter analyze` and the group’s unit tests before starting the next group.
- Cross-cutting rules (mechanics #1–#7) apply to **every** conversion — do not skip them when a task feels “small.”

### Cross-cutting checklist (paste into every PR / group review)

| # | Rule | Fail mode if skipped |
|---|------|----------------------|
| 1 | Side effects only in `BlocListener` (snackbar, `Navigator.pop`, parent callbacks) | Duplicate snackbars, pops during rebuild, “setState during build” |
| 2 | Emit **new** collections (`[...x]`, `Map.of`, `Set.of`) — never mutate then re-emit | Equatable no-op → UI stuck |
| 3 | Controllers / FocusNode / TabController / ScrollController stay **widget-local** | Leaks, dispose crashes, cursor jumps |
| 4 | Replace `mounted` with Bloc `isClosed` / emit-after-close safety | Crash after dispose; masters bulk-sync post-loop bug |
| 5 | Progressive multi-emit in one handler (cache→live, per-type sync loop) | Blank spinner or all-or-nothing UX |
| 6 | Cache-then-live: initial state = cached rows + `isLoading: true` | Instant-paint regression |
| 7 | Inject DI + cross-bloc inputs in constructor; no `context` after `await` | Stale/wrong context, post-await read bugs |

### Provisioning pattern (confirm once, reuse everywhere)

Local (page/dialog-scoped) providers — **do not** add migration blocs to `app.dart` `MultiBlocProvider`.

Canonical example: `VoucherPdfActionsWidget` wraps itself in:

```dart
BlocProvider(
  create: (_) => SomeBloc(deps...),
  child: ...,
)
```

Also used: `BlocProvider.value` when reusing a parent-owned instance (see dashboard patterns).

---

## Phase 0 — Foundations & decisions

### Task 0.1 — Baseline & tooling
- [ ] Grep `setState(` under `lib/` and save a baseline file list (expect ~24 real files + `sales_return_dialog` + false positive in voucher PDF).
- [ ] Confirm packages: `flutter_bloc: ^9.1.1`, `bloc: ^9.2.1` — **no upgrade**.
- [ ] Confirm **do not** add `bloc_concurrency` / `hydrated_bloc` / `replay_bloc` unless a later task explicitly needs them (plan says Timer debounce only).
- [ ] Skim one existing `*_bloc_test.dart` (e.g. `test/receipt_bloc_test.dart`) for `bloc_test` style and fake-repo patterns.

**Acceptance:** Baseline list written; team agrees on local-provider pattern.

### Task 0.2 — Conventions lock-in
- [ ] States use `Equatable` (or equivalent props) for new classes.
- [ ] Events/states as separate files when matching existing feature style, or co-located if feature is tiny — pick one style per feature folder and stick to it.
- [ ] File placement:
  - Feature-specific: `lib/ui/features/<feature>/bloc/` or `cubit/`
  - Shared core: `lib/ui/core/bloc/` (or `cubit/`) for `GpsCaptureBloc`, `ListFilterCubit`, etc.
- [ ] Naming: `XxxBloc` / `XxxCubit`, `XxxEvent`, `XxxState` (sealed/freezed optional; match repo style — currently plain classes + Equatable).

**Acceptance:** Conventions noted in this file / PR description; no global DI registration of page-scoped blocs.

### Task 0.3 — `SortableReportScaffold` capability check
- [ ] Confirm scaffold is already `StatelessWidget` (no `TickerProvider`) → report pages can become fully `StatelessWidget`.
- [ ] Note which reports pass date props vs omit them (stock, aging, order status differ).

**Acceptance:** Decision recorded: report pages → `StatelessWidget` + local `BlocProvider`.

### Task 0.4 — Scope gap: `sales_return_dialog.dart` → **INCLUDE** (design locked)

**Full design:** [`docs/sales_return_dialog_design.md`](sales_return_dialog_design.md)

| Decision | Choice |
|----------|--------|
| In scope? | **Yes** — required for zero real `setState(` under dashboard widgets |
| Type | **`SalesReturnQuickCubit`** (not Bloc; not global `SalesReturnBloc`) |
| Why not `SalesReturnBloc` | Global editor state (`editingItems` / customer) — same contamination risk as invoice sheet + `SalesInvoiceBloc` |
| Placement | `lib/ui/features/dashboard/cubit/sales_return_quick_cubit.dart` |
| Provider | Local `BlocProvider` wrapping the dialog in `_launchSalesReturnFlow` only |
| Controllers / form | Stay widget-local; cubit owns `eligibleItems`, `selectedItem`, `matchingInvoices`, `quantities`, `submitting`, success/error |
| Submit fixes | try/catch, double-tap guard, listener for pop/snackbar/`onReturnConfirmed` |
| Preserve | Hardcoded reason `'Damaged packaging'`, `RET-TEMP-` prefix, max-qty form validators |
| Schedule | Phase 6 (or with Group B); independent of Group I |

**Implementation checklist (from design §13):**
- [ ] **0.4.1** Pure helpers: eligible items + matching invoices (+ unit tests).
- [ ] **0.4.2** `SalesReturnQuickState` + cubit (`loadEligibleItems`, `selectItem`, `setQuantity`, `submit`).
- [ ] **0.4.3** `test/sales_return_quick_cubit_test.dart` (success, throw, double-submit, empty history, canSubmit).
- [ ] **0.4.4** Refactor dialog UI: builder/listener; remove all `setState`; controller recreate on item change.
- [ ] **0.4.5** Wire `BlocProvider` in `_launchSalesReturnFlow` (hook `DailyStatsCubit.refresh` after Group B).
- [ ] **0.4.6** Manual: empty history, multi-invoice happy path, max-qty validation, double-tap, save failure.
- [ ] **0.4.7** Confirm editor/list still only use global `SalesReturnBloc`.
- [ ] **0.4.8** Grep dialog → zero `setState(`.

**Acceptance:** Design doc followed; dialog has no `setState`; global return editor unaffected; cubit tests green.

**Inventory impact:** +1 Cubit → 5 Bloc + **7** Cubit + invoice reuse; **25** files in setState conversion set.

---

## Phase 1 — Group A: Reports (13 pages, 1 generic `ReportBloc`)

**Why first:** Largest boilerplate win; fully independent; validates generic-bloc + cache-then-live + listener snackbars.

### Task 1.1 — Design `ReportState<T>` / `ReportEvent` / `ReportBloc<T>`
**Files to create:**
- `lib/ui/features/reports/bloc/report_state.dart`
- `lib/ui/features/reports/bloc/report_event.dart`
- `lib/ui/features/reports/bloc/report_bloc.dart`

**Do:**
- [ ] `ReportState<T>`: `isLoading`, `rows: List<T>`, `range: DateTimeRange?` (or `start`/`end`), `sortField: Object?` (or second generic `S`), `sortAscending`, `error: String?`, optional flags if needed (`isLiveData` for stock — see Task 1.4).
- [ ] Events: `RefreshReport`, `SetDateRange(DateTimeRange?)`, `SetSort(Object field, {bool? ascending})`.
- [ ] `ReportBloc<T>` parameterized by injectables:
  - local seed (sync): `List<T> Function()` or pre-read list
  - remote fetch (async): `Future<List<T>> Function()`
  - optional mapper
- [ ] Constructor seeds **initial state** with cached rows + `isLoading: true` when cache exists (mechanics #6). If cache empty, still may start loading.
- [ ] `on<RefreshReport>`: reentrancy guard `if (state.isLoading) return` (or droppable semantics equivalent).
- [ ] Progressive emit: loading → success (rows, clear error) or failure (keep previous rows, set `error`).
- [ ] `SetDateRange` / `SetSort`: pure state updates (no re-fetch unless product requires it — today filters are client-side in `_buildReport`).
- [ ] Emit **new** list instances for `rows`.

**Edge cases:**
| Case | Required behavior |
|------|-------------------|
| Fetch fails offline | Keep cached `rows`; set `error`; do **not** clear list |
| Double pull-to-refresh | Second refresh ignored while `isLoading` |
| Date clear (`onClearDate`) | `SetDateRange(null)` |
| Sort toggle same field | Flip `sortAscending` |
| Sort new field | Set field + default ascending policy **per page** (name often asc, total often desc) — either pass default in event or keep default flip logic in widget when dispatching |
| Widget disposed mid-fetch | No emit-after-close crash |
| Aggregation | **Not** in bloc — pure `buildReport(state)` per page |

**Acceptance:** Generic bloc compiles; unit tests cover cache seed, success overwrite, failure keep-cache + error, reentrancy, sort/range state only.

### Task 1.2 — Unit tests for `ReportBloc<T>`
- [ ] `test/report_bloc_test.dart` using `bloc_test`.
- [ ] Sequences: initial cached+loading → live rows; fail keeps cache; refresh while loading no-op; `SetSort` / `SetDateRange` emit without touching rows source.

### Task 1.3 — Migrate “standard invoice-aggregate” reports (template first)
Migrate one representative page fully, then clone the pattern.

**Pilot:** `item_sales_report_page.dart`

- [ ] Convert to `StatelessWidget` (or thin shell only if needed).
- [ ] `BlocProvider(create: (_) => ReportBloc<...>(local: ..., remote: ...))` — inject `HiveDatabaseService` / `ZohoApiClient` via `sl<>` in create, not via context after await.
- [ ] `BlocListener` on `error` → `showErrorSnackBar` once (clear error after show, or listen with `listenWhen` on transition to non-null error).
- [ ] `BlocBuilder` / `context.watch` for loading, rows, range, sort.
- [ ] Keep page-specific `_SortField` enum + comparator switch in the page.
- [ ] Keep `_buildReport()` as pure function reading range/sort from state.
- [ ] Wire scaffold: `onRefresh` → `RefreshReport`, date taps → `SetDateRange`, sort → `SetSort`.

**Then apply same pattern to:**
- [ ] `sales_summary_by_customer_item_report_page.dart`
- [ ] `sales_summary_by_customer_value_report_page.dart`
- [ ] `customerwise_returns_summary_report_page.dart`
- [ ] `itemwise_returns_summary_report_page.dart`
- [ ] `itemwise_orders_summary_report_page.dart`
- [ ] `orders_summary_by_customer_report_page.dart`
- [ ] `invoice_receipts_summary_report_page.dart`
- [ ] `expense_summary_report_page.dart`

**Edge cases per page:**
- Initial `initState` cache source differs (`getLocalInvoices`, orders, expenses, returns) — inject correct local/remote pair.
- Date filtering **before** aggregation must still use state’s range inside pure builder.
- Currency / org context stays in widget (`context.org`), not bloc.

### Task 1.4 — Variant: `stock_report_page.dart`
**Differences from standard template:**
- No date range UI.
- Remote: `fetchItems(locationId)` with `assignedWarehouseId`.
- Offline fallback to `_db.getItems()`.
- Tracks `_isLiveData` (banner/UX for live vs cache).

**Do:**
- [ ] Either extend `ReportState` with optional `isLiveData` / metadata, or use a small typed row payload / side flag on a stock-specific subclass.
- [ ] Local seed + remote fetch + failure keep previous items.
- [ ] Sort only (no date events used).

**Edge cases:**
- Empty `locationId` — preserve current API call behavior (don’t invent new warehouse logic).
- Live success should set live flag; offline fallback should leave live=false.

### Task 1.5 — Variant: `order_status_report_page.dart`
**Differences:**
- Constructor params: `OrderStatusFilter filter`, `title`.
- Cache: `getLocalOrders()`; remote: `fetchSalesOrders()`.
- Filter buckets applied in pure builder (`readyOrPending` / `invoiced` / `delayed`) — **not** in bloc (same raw list for all filters; widget filters).
- No date range (confirm UI).

**Edge cases:**
- Same raw list served to different filter UIs — bloc holds **all** orders; page filters by `widget.filter`.
- Do not bake filter into bloc state unless you create separate instances per filter (preferred: filter stays in widget).

### Task 1.6 — Multi-list: `aging_receivables_report_page.dart`
**Differences:**
- Cache seeds **two** sources: open invoices + customer name map.
- Live: parallel-ish fetch of open invoices + customers.
- Aggregation: aging buckets pure function.
- Loading flag currently named `_isSyncing`.

**Do:**
- [ ] Define typed payload `T` e.g. `AgingReportData { List<OpenInvoice> invoices; Map<String,String> names; }` rather than forcing single list.
- [ ] Thin subclass or dedicated fetch fns for this page.
- [ ] Failure: keep cached invoices+names; error snackbar via listener.

**Edge cases:**
- Balance `<= 0` skipped in aggregation (preserve).
- Bucket boundaries 0–15 / 15–30 / 30–60 / >60 day math unchanged.
- Reentrancy on refresh.

### Task 1.7 — Multi-list: `transactions_summary_report_page.dart`
**Differences:**
- Four parallel lists via `Future.wait` (invoices, receipts, expenses, returns — confirm exact set in file).
- Date range + multi-series aggregation in pure builder.

**Do:**
- [ ] Typed payload record as `T` holding the four lists.
- [ ] Remote fetch uses `Future.wait`; failure keeps all four cached collections.
- [ ] Progressive loading semantics preserved.

**Edge cases:**
- Partial `Future.wait` failure: match current behavior (likely all-or-nothing catch) — do not silently drop one list unless code already does.
- Sort/date interactions across combined series.

### Task 1.8 — Group A verification
- [ ] `flutter analyze` clean for reports.
- [ ] `flutter test test/report_bloc_test.dart`.
- [ ] Manual (at least 3 reports + aging + stock + order status + transactions):
  - [ ] Instant paint from cache before network returns.
  - [ ] Kill network → error snackbar + data remains.
  - [ ] Date range set/clear + sort toggles.
  - [ ] Pull-to-refresh reentrancy (spam refresh).
- [ ] Grep `setState(` in `lib/ui/features/reports/` → **zero**.

---

## Phase 2 — Shared primitives: `ListFilterCubit` + GPS (Groups E core + F prep)

**Why next:** One filter cubit reused by customer selector, item search, invoice flow; GPS shared by two dialogs.

### Task 2.1 — `ListFilterCubit<T>`
**File:** `lib/ui/core/cubit/list_filter_cubit.dart` (path flexible; keep under `core`).

**Do:**
- [ ] State: `query`, `allItems`, `filtered` (or derive filtered via getter).
- [ ] Methods: `setItems(List<T>)`, `setQuery(String)`, optional `setPredicate`.
- [ ] Predicate injectable: `(T item, String query) => bool` so customers (name/company/phone) vs items (name/sku) differ.
- [ ] Emit new filtered lists every time (mechanics #2).

**Edge cases:**
| Case | Behavior |
|------|----------|
| Empty query | Show full list |
| Case-insensitive match | Preserve current widget behavior |
| `setItems` after query set | Re-filter with current query |
| Items list identity | Don’t mutate input list |

**Acceptance:** Unit test for empty/query/setItems re-filter.

### Task 2.2 — `GpsCaptureBloc`
**File:** `lib/ui/core/bloc/gps_capture_bloc.dart` (+ event/state files as needed).

**Do:**
- [ ] States: `idle`, `capturing`, `captured(lat, lng, {Customer? enriched})`, `permissionDenied`, `serviceDisabled`, `failed(message)`.
- [ ] Event: `GpsCaptureRequested({Customer? customer, bool persist})` (and/or internal stage events if you model a full machine).
- [ ] Capture core (must match both call sites):
  - Permission via **`permission_handler`** `Permission.locationWhenInUse` (not geolocator permission APIs).
  - `Geolocator.isLocationServiceEnabled()`.
  - `Geolocator.getCurrentPosition(desiredAccuracy: high, timeLimit: 12s)`.
- [ ] **Persist mode** (selector sheet): `repo.updateCustomerGps`; best-effort `ZohoApiClient.updateCustomerGps` only if id is **not** `temp_`; on Zoho fail enqueue `customer_gps_update` `SyncQueueItem` + fire-and-forget `syncPendingItems`; return enriched `Customer`.
- [ ] **Capture-only mode** (create dialog): no repo/Zoho/queue; just lat/lng.
- [ ] Zoho failure in persist mode must **not** become user-facing error (swallowed today).
- [ ] Inject `SalesRepository`, `ZohoApiClient`, `SyncWorker` (or interfaces) via constructor.

**Edge cases:**
| Case | Behavior |
|------|----------|
| Permission denied | `permissionDenied` state; UI snackbar via listener |
| Location services off | `serviceDisabled` |
| Timeout (12s) | `failed` with message |
| `temp_` customer id | Skip live Zoho update; still local update if persist |
| Double-tap capture | Ignore while `capturing` |
| Dispose mid-GPS | isClosed guard |
| Retry after failure | Allow new `GpsCaptureRequested` from idle/error |

**Acceptance:** Unit tests with fakes for permission/geolocator if practical; at minimum pure persist-path logic for temp vs permanent ids.

### Task 2.3 — Wire GPS into `customer_selector_sheet.dart` (persist mode)
- [ ] Provide `GpsCaptureBloc` via local `BlocProvider` around GPS dialog/sheet section.
- [ ] Replace `StatefulBuilder` capturing flag + duplicated GPS body with `BlocBuilder`/`BlocListener`.
- [ ] Listener: snackbars + `Navigator.pop(enrichedCustomer)` on success.
- [ ] Search filter: replace `StatefulBuilder` filtered list with `ListFilterCubit<Customer>` (predicate: name/company/phone as today).

**Edge cases:**
- Nested `StatefulBuilder` removal must not break sheet rebuild of parent list.
- Controllers for search stay widget-local; dispose correctly.
- Selecting customer vs capturing GPS are independent paths.

### Task 2.4 — Wire GPS + create flow into `create_customer_dialog.dart`
See Group E remainder in Phase 3 Task 3.x for `CreateCustomerCubit`; GPS portion:

- [ ] Same `GpsCaptureBloc` in capture-only mode (`persist: false`).
- [ ] On `captured`, write lat/lng into existing text controllers (widget-local) via listener.
- [ ] Capturing spinner from bloc state, not `setState`.

### Task 2.5 — Group F: `item_search_sheet.dart`
- [ ] Replace `_filtered`/`_query` + `setState` with `ListFilterCubit<Item>` (name/sku predicate).
- [ ] Convert to Stateless + provider, or keep Stateful only if controllers require it.
- [ ] Search controller stays widget-local; `onChanged` → `cubit.setQuery`.

**Edge cases:**
- Empty items list; query with no matches → empty UI unchanged.
- Sheet dispose cancels nothing async (sync filter).

### Task 2.6 — Phase 2 verification
- [ ] `flutter analyze`.
- [ ] Manual GPS: permission deny, services off, success fill coords (create), success persist+pop (selector).
- [ ] Manual filters: customer sheet + item sheet search.
- [ ] Grep `setState` in those three files → zero.

---

## Phase 3 — Group E remainder: `CreateCustomerCubit`

### Task 3.1 — `CreateCustomerCubit`
**File:** e.g. `lib/ui/features/dashboard/cubit/create_customer_cubit.dart` or under `core` if shared.

**Do:**
- [ ] States: `initial` / `saving` / `success(Customer)` / `failure(String)`.
- [ ] `submit({required fields...})` receives **already validated** trimmed values from widget (8 controllers + form key stay widget-local).
- [ ] Build `Customer` with `temp_cust_<ts>` id.
- [ ] **Inject `activeRouteId`** with triple fallback evaluated **before** await:  
  `RouteBloc.state.activeRouteId ?? salesRepo.activeRouteId ?? 'route_default'` — pass into cubit method/ctor; **never** `context.read` after await.
- [ ] `saveCustomers`, build Zoho payload including `cf_latitude`/`cf_longitude` when present, `enqueueSyncItem`.
- [ ] try/catch → `failure` (fixes wedged `_isSaving` bug).
- [ ] Widget `BlocListener`: on success → `RouteBloc.add(LoadRoutes())`, fire-and-forget `syncPendingItems`, `Navigator.pop(newCustomer)`, snackbar, `onCustomerCreated`.

**Edge cases:**
| Case | Behavior |
|------|----------|
| Validation fails | Cubit never called |
| Double-tap save | Ignore if already `saving` |
| Throw mid-save | `failure`; spinner clears; dialog stays open |
| Offline enqueue | Still success path if local save works (match current) |
| GPS fields empty | Payload omits custom fields |

### Task 3.2 — Integrate into dialog UI
- [ ] Remove `_isSaving` setState paths.
- [ ] GPS via Task 2.4.
- [ ] Button enabled/disabled from cubit state + form validity (form validity may still be local).

### Task 3.3 — Verification
- [ ] Manual: happy path create; force throw (mock) → no wedged spinner; GPS fill-only; route reload after create.
- [ ] Grep create dialog + selector → no `setState`.

---

## Phase 4 — Independent groups (B, C, D, G, H, J)

These can be parallelized after Phase 2–3 primitives exist (J independent; B independent; etc.).

---

### Group B — `dashboard_page.dart`

#### Task 4.B.1 — `DashboardNavCubit`
- [ ] `Cubit<int>` (or state object) for bottom-nav / sidebar `_currentIndex`.
- [ ] Provide **page-scoped** on `DashboardPage` (not global app.dart unless already pattern-breaking).
- [ ] All tab switches call cubit; builders read cubit state.

#### Task 4.B.2 — `DailyStatsCubit`
- [ ] State holds: `todaySales`, `todayPayments`, `todayExpenses`, `todayReturns`, `completedDeliveries`.
- [ ] `refresh()` re-queries Hive (same aggregation as `_loadDailyStats`).
- [ ] Inject `HiveDatabaseService`.
- [ ] Replace **every** `_loadDailyStats()` call site:
  - initState / open
  - after invoice flow, payment, sales return
  - after cash closing, issue-to-van, stock-unloading
  - any `.then((_) => _loadDailyStats())` navigation returns
  - client operations callbacks

**Edge cases:**
| Case | Behavior |
|------|----------|
| Stats query throws | Don’t crash dashboard; prefer catch + keep last stats or zeros |
| Concurrent refresh | Last-write-wins OK for local sums; optional ignore-if-busy |
| Today boundary | Preserve current “all local records” vs true calendar-day filter if that’s what code does today (do not silently change business meaning) |
| Nav cubit + stats cubit both present | Prefer `MultiBlocProvider` at dashboard root |

#### Task 4.B.3 — Convert dashboard shell
- [ ] Remove remaining `setState` for index + stats (3+ call sites).
- [ ] Keep existing reads of `ThemeCubit`, `SyncBloc`, sales blocs unchanged.

#### Task 4.B.4 — Verify Group B
- [ ] Manual: switch tabs; complete invoice/payment/return; confirm metrics refresh.
- [ ] Grep `dashboard_page.dart` for `setState` → zero.

---

### Group C — `receipt_payment_dialog.dart` → `ReceiptAllocationBloc`

#### Task 4.C.1 — Model events & state
**Events (complete list):**
- [ ] `ReceiptAllocationStarted`
- [ ] `OpenInvoicesRefreshRequested` (internal / after start)
- [ ] `PaymentAmountChanged(String raw)`
- [ ] `PaymentModeChanged(String mode)`
- [ ] `InvoiceAllocationEdited(invoiceId, invoiceNumber, String value)`
- [ ] `ReceiptSubmitted`

**State fields:**
- [ ] `paymentMode`, `openInvoices`, `allocations`, `canSubmit`, `submitting`, `submitError` / `submitSuccess`, optional `amount` mirror if needed.

#### Task 4.C.2 — Implement FIFO & allocation rules
- [ ] **FIFO source of truth:** `_allocations` model in bloc; controller text is downstream mirror.
- [ ] Amount change **only** trigger that re-runs FIFO (not payment mode).
- [ ] Manual row edit mutates that invoice’s allocation **without** full FIFO re-run.
- [ ] Rounding: preserve `toStringAsFixed(2)` intermediate remaining logic.
- [ ] `canSubmit` ports `_isFormValid()` (amount > 0, no over-allocation vs invoice balance, total allocated ≤ amount, etc.).

#### Task 4.C.3 — Cache-then-live open invoices
- [ ] Start: seed customer open invoices sorted date-asc from Hive.
- [ ] Then `syncMaster(MasterType.openInvoices)`; re-read Hive; on failure **silent keep cache** (no wipe, no error toast for refresh fail).
- [ ] **Product decision (must implement explicitly):** if live refresh lands mid-edit, either:
  - (A) re-run FIFO from current amount (current-ish behavior — may clobber manual overrides), or
  - (B) preserve manual overrides when user has edited (safer UX).  
  Document choice in code comment.

#### Task 4.C.4 — Submit path (latent bug fixes)
- [ ] Guard double-tap with `submitting`.
- [ ] try/catch → failure state (dialog not wedged).
- [ ] Build temp `ReceiptVoucher`, `saveLocalReceipt`, `enqueueSyncItem`, fire-and-forget `syncPendingItems`.
- [ ] Listener: pop + success snackbar + `onPaymentLogged`.

#### Task 4.C.5 — Widget reconciliation
- [ ] `_amountController`, `_allocationControllers`, `_allocationFocusNodes` stay widget-local.
- [ ] Amount controller listener → `PaymentAmountChanged`.
- [ ] **Focus-aware** `BlocListener`: only set allocation controller `.text` when `!focusNode.hasFocus` and text differs (current L124–131).
- [ ] Create missing controllers when new invoices appear; dispose removed ones carefully on dialog dispose (and when invoice list identity changes).

**Edge cases matrix:**
| Case | Behavior |
|------|----------|
| Empty open invoices | canSubmit false; no crash |
| Amount 0 / empty | FIFO clears allocations |
| Focused row during FIFO | That row’s text not overwritten |
| Over-allocate one invoice | canSubmit false |
| Total allocated > amount | canSubmit false |
| Negative parse | treat as 0 / invalid per current |
| Offline submit | local save success path if that’s current |
| Double Log Receipt | second ignored while submitting |
| Refresh mid-manual-edit | per decision A/B above |
| Dispose mid-syncMaster | no emit after close |

#### Task 4.C.6 — Tests
- [ ] `test/receipt_allocation_bloc_test.dart`:
  - FIFO order oldest-first
  - Manual edit doesn’t re-FIFO siblings unexpectedly
  - canSubmit boundaries
  - submitting guard
  - refresh failure keeps cache
  - submit success/failure sequences

#### Task 4.C.7 — Verify Group C
- [ ] Manual: FIFO while typing; edit one row with focus; double-tap submit; offline; refresh mid-edit.
- [ ] Grep dialog → no `setState`.

---

### Group D — `masters_sync_page.dart` → `MastersSyncBloc`

#### Task 4.D.1 — Events & state
**Events:**
- [ ] `MastersSyncStarted` — subscribe `SyncRepository.syncStatusStream`; cancel in `close()`.
- [ ] `SyncStatusLogReceived(String status)`
- [ ] `SyncOneRequested(MasterType)`
- [ ] `SyncAllRequested`
- [ ] `ConsoleLogsCleared`

**State:**
- [ ] Per-type: in-flight set, last error map, synced types set (all **new instances** on change).
- [ ] Bulk: `_bulkInFlight`, bulk status/success banner fields.
- [ ] `consoleLogs` bounded list (max 100).
- [ ] `hasCoreMasters` bool (recomputed after each sync) for PROCEED button.

#### Task 4.D.2 — Handlers
- [ ] Log append: timestamped line; emit new list; if length > 100 drop oldest via new list (not in-place `removeAt` on same ref).
- [ ] `SyncOneRequested`: ignore if type in-flight or bulk in-flight.
- [ ] `SyncAllRequested`: ignore if bulk in-flight; loop `MasterType.values` with progressive emits (start → per-type success/fail → done).
- [ ] Post-loop status write must be emit-safe if closed (fixes unguarded dispose bug).
- [ ] Errors **inline only** (per-type subtitle + Retry, bulk banner) — **no snackbars** in this page.

#### Task 4.D.3 — Widget wiring
- [ ] `_tabController` + `_scrollController` stay widget-local (`SingleTickerProviderStateMixin` retained if needed).
- [ ] Auto-scroll console: `BlocListener` on logs length change → scroll (mechanics #3).
- [ ] Cross-bloc: `RouteBloc.add(LoadRoutes())`, `SyncBloc`/`AuthBloc` actions remain **widget-side** listeners on completed sync outcomes — not inside MastersSyncBloc.
- [ ] PROCEED enabled from `state.hasCoreMasters`.

**Edge cases:**
| Case | Behavior |
|------|----------|
| Spam tap one master | Deduped while in-flight |
| Sync all while one running | Guarded |
| Log flood > 100 | Cap; UI still rebuilds (new list) |
| CLEAR logs | Emit empty **new** list |
| Navigate away mid bulk | No crash; subscription cancelled in `close()` |
| Retry pill | Same as `SyncOneRequested` |
| hasCoreMasters false→true | PROCEED enables without manual rebuild hack |

#### Task 4.D.4 — Tests
- [ ] Progressive bulk emit sequence.
- [ ] Log bound at 100.
- [ ] Dedup guards.
- [ ] `hasCoreMasters` updates (fake repo).

#### Task 4.D.5 — Verify Group D
- [ ] Manual: sync one, sync all, clear logs, PROCEED after core masters, leave page mid-sync.
- [ ] Grep masters page → no `setState`.

---

### Group G — `item_line_editor_dialog.dart` → `LineEditorCubit`

#### Task 4.G.1 — Cubit
- [ ] Hold typed `quantity`, `rate`, `discount` (not raw strings as source of truth).
- [ ] Derived: `subtotal`, `tax`, `total` as state getters or computed fields.
- [ ] Methods: `updateQuantity`, `updateRate`, `updateDiscount` (parse safely).
- [ ] Seed from initial line values when dialog opens.

#### Task 4.G.2 — Widget
- [ ] Controllers remain for input UX; `onChanged` → cubit updates (replace `setState(() {})`).
- [ ] Display totals from `context.watch<LineEditorCubit>()`.
- [ ] Confirm/`Navigator.pop` uses **cubit.state** values, not controller text (avoid parse drift).

**Edge cases:**
| Case | Behavior |
|------|----------|
| Empty / non-numeric field | Treat as 0 or last valid — match current parse behavior |
| Negative values | Preserve current validation if any |
| Tax % from item | Unchanged formula |
| Dispose | Controllers disposed; cubit closed by provider |

#### Task 4.G.3 — Verify
- [ ] Manual: type qty/rate/discount; totals live-update; confirm returns correct triple.
- [ ] Grep file → no `setState`.

---

### Group H — `route_page.dart` → `RouteSelectionUiCubit`

#### Task 4.H.1 — Cubit
- [ ] `Cubit<String?>` for `_selectedRouteId` (pre-confirm highlight only).
- [ ] **Page-scoped** `BlocProvider` on `RouteSelectionPage` — **not** global.
- [ ] Do **not** fold into `RouteBloc` (that owns list/loading/`SelectActiveRoute`).

#### Task 4.H.2 — Widget
- [ ] Card highlight from UI cubit; confirm button still dispatches existing `RouteBloc` event.

**Edge cases:**
- Selecting same route twice; null initial; list reloads from `RouteBloc` while UI selection points at removed id (clear or keep — match current).

#### Task 4.H.3 — Verify
- [ ] Manual: highlight then confirm active route.
- [ ] Grep route page → no `setState`.

---

### Group J — `async_search_widget.dart` → `AsyncSearchBloc`

#### Task 4.J.1 — Bloc design
**Correction from plan:** no `searchCustomers`/`searchItems` on repository — **in-memory filter** over `getCustomers()` / `getItems()`.

**Events:**
- [ ] `SearchTypeChanged(SearchType)` — also clears query/results.
- [ ] `SearchQueryChanged(String)` — 400ms debounce.
- [ ] `SearchCleared`.

**States:** idle / loading / results(customers|items) / empty (+ optional error only if source can throw).

#### Task 4.J.2 — Debounce without race
- [ ] Keep `Timer` debounce **inside** bloc; cancel timer in `close()`.
- [ ] **Drop artificial `Future.delayed(500ms)`** — filter synchronously after debounce so out-of-order results cannot win.
- [ ] Do not add `bloc_concurrency` unless product insists on keeping fake latency (then `restartable()`).

**Matching rules (preserve):**
- Customers: name/company case-insensitive + phone on raw query.
- Items: name/sku.

#### Task 4.J.3 — Widget
- [ ] Controllers/segmented control widget-local.
- [ ] Results via `BlocBuilder`; no snackbars unless you add errors later.

**Edge cases:**
| Case | Behavior |
|------|----------|
| Rapid typing | Only last debounced query applies |
| Clear during debounce | Cancel pending; empty/idle |
| Toggle type mid-debounce | Clear + cancel timer; no wrong-type list |
| Empty query after search | Match current (idle vs empty) |
| Large lists | Sync filter OK on UI isolate for now (same as today) |

#### Task 4.J.4 — Tests
- [ ] Debounce: use `blocTest` with `wait` or fake async.
- [ ] Type toggle clears results.
- [ ] No stale overwrite (regression for removed delay).

#### Task 4.J.5 — Verify
- [ ] Manual: type fast, clear, toggle customer/item.
- [ ] Grep widget → no `setState`.

---

## Phase 5 — Group I: Invoice flow → existing `SalesInvoiceBloc` (highest risk)

**Do last.** Structural change on global shared cart.

### Task 5.1 — Remove `_localCart`; bind to `SalesInvoiceState.cart`
- [ ] Wrap sheet in `BlocBuilder<SalesInvoiceBloc, SalesInvoiceState>` (bloc already global from `app.dart`).
- [ ] Per-row qty: `state.cart[item] ?? 0` (cart getter from `editingItems`).
- [ ] Subtotal/tax/total still computed in **widget** from `state.cart` (bloc has no totals API).
- [ ] Mapping:
  | UI action | Event |
  |-----------|--------|
  | ADD / + | `AddToCart(item, 1)` |
  | − | `UpdateCartQuantity(item, currentQty - 1)` (removes at ≤0) |
  | remove | `RemoveFromCart(item)` |
  | checkout | `CheckoutRequested(customer, notes)` — **no** ClearCart+replay |

### Task 5.2 — CRITICAL: `ClearCart` on open
- [ ] On sheet open (`initState` / first frame): `context.read<SalesInvoiceBloc>().add(ClearCart())`.
- [ ] Rationale: global `SalesInvoiceBloc` co-used by `sales_invoice_editor_page` and `StartInvoiceFromOrder`; without clear, sheet inherits stale/half-edited lines.

**Edge cases:**
| Case | Behavior |
|------|----------|
| Editor has draft items, user opens van invoice sheet | Sheet starts **empty** |
| Order conversion populated cart, then sheet opened | Cleared on open |
| User closes sheet mid-cart | Cart may remain until next open clear — acceptable if open always clears |
| Checkout success | Existing bloc clears? confirm; still clear on next open |
| Concurrent editor + sheet | Should not be possible in nav; if possible, document risk |

### Task 5.3 — Stock guard feedback via bloc
- [ ] Remove local clamp + direct snackbar for over-stock.
- [ ] `BlocListener` on `errorMessage` / `InsufficientStockException` path → `showErrorSnackBar('Cannot exceed available van stock')` (or message from state).
- [ ] Ensure rejected increment does not leave UI desynced (qty stays previous).

### Task 5.4 — Search via `ListFilterCubit<Item>`
- [ ] Seed items from one-shot `_db.getItems()` (init) into filter cubit.
- [ ] Search controller widget-local.

### Task 5.5 — Checkout / callback wiring
- [ ] Listen for checkout success → `onInvoiceSubmitted`, pop sheet, snackbars as today.
- [ ] Credit limit / other existing bloc errors still surface via listener.

### Task 5.6 — Regression: editor + order conversion **must remain unaffected**
- [ ] Manually open sales invoice editor: add lines, save, edit existing.
- [ ] Convert sales order → invoice (`StartInvoiceFromOrder`) end-to-end.
- [ ] Confirm no new events required on `SalesInvoiceBloc` (reuse only).

### Task 5.7 — Tests
- [ ] Extend or add tests around cart events if missing: `AddToCart` stock failure emits error; `ClearCart` empties; `UpdateCartQuantity` to 0 removes.
- [ ] Optional widget test: sheet dispatches ClearCart on open (if harness allows).

### Task 5.8 — Verify Group I
- [ ] **Highest priority manual script:**
  1. Open invoice editor, add items, back out without completing.
  2. Open invoice flow sheet for a customer → cart **empty**.
  3. Add / increment / decrement / remove.
  4. Increment past van stock → snackbar, qty not increased.
  5. Checkout happy path → stats refresh (DailyStats) if wired.
  6. Order → invoice conversion still works.
- [ ] Grep `invoice_flow_sheet.dart` → no `setState`, no `_localCart`.

---

## Phase 6 — `sales_return_dialog.dart` (`SalesReturnQuickCubit`)

**Design locked:** [`docs/sales_return_dialog_design.md`](sales_return_dialog_design.md). Execute Task **0.4.1–0.4.8**.

### Task 6.1 — Implement cubit + helpers
- [ ] Pure query helpers + `SalesReturnQuickCubit` per design §§5–9.
- [ ] Inject `SalesRepository` + sync trigger; do **not** touch global `SalesReturnBloc`.

### Task 6.2 — Wire dialog + dashboard
- [ ] Provider-scoped dialog; controllers/form widget-local; `BlocListener` for success/error side effects.
- [ ] Edge matrix: design §11 (empty history, item switch controller dispose, double-tap, throw, max qty, multi-invoice partial qty).

### Task 6.3 — Verify
- [ ] Unit tests green; manual checklist design §13 / 0.4.6.
- [ ] Grep dialog → no `setState`; editor return flow still works.

---

## Phase 7 — Final verification & cleanup

### Task 7.1 — Static & tests
- [ ] `flutter analyze` (whole project).
- [ ] `flutter test` (full suite).
- [ ] Minimum new tests present:
  - [ ] `ReportBloc`
  - [ ] `ReceiptAllocationBloc` (FIFO + guards)
  - [ ] Sales invoice cart behaviors touched by Group I
  - [ ] Ideally: `MastersSyncBloc` progressive emit, `AsyncSearchBloc` debounce, `ListFilterCubit`, `CreateCustomerCubit` failure path, `GpsCaptureBloc` temp-id path

### Task 7.2 — Grep gate
- [ ] `rg "setState\(" lib` (or IDE search):
  - Zero real hits, **or**
  - Only residual: deferred `sales_return_dialog` if explicitly accepted.
  - False positive OK: `voucher_pdf_bloc.dart` `_onResetState`.

### Task 7.3 — Manual regression checklist (full)

**Reports**
- [ ] Cache paint, fail-soft, date/sort, pull refresh (sample 3 + aging + stock + order status + transactions).

**Receipt**
- [ ] FIFO + focused row no cursor jump.
- [ ] Double-tap Log Receipt.
- [ ] Offline submit.
- [ ] Live refresh mid-edit (decision A/B).

**Masters**
- [ ] Logs stream + cap 100 rebuild.
- [ ] PROCEED reactive.
- [ ] Leave page mid bulk sync.

**GPS / customer**
- [ ] Capture-only vs persist modes.
- [ ] Permission denied / services off.
- [ ] Create customer throw → no wedge.

**Dashboard**
- [ ] Tab nav.
- [ ] Stats after each transactional flow.

**Line editor / filters / route**
- [ ] Live totals; item/customer search; route highlight+confirm.

**Invoice flow (critical)**
- [ ] ClearCart-on-open vs editor/order cart.
- [ ] Stock snackbar via bloc.
- [ ] Full cart + checkout.
- [ ] Editor + order conversion still good.

**Async search**
- [ ] Rapid type, clear, type toggle mid-flight.

### Task 7.4 — Docs / handoff
- [ ] Update this tasks file checkboxes to reflect done work.
- [ ] Note any intentional product decisions (receipt refresh vs manual allocations, sales_return_dialog scope).
- [ ] Do **not** leave temporary debug prints.

---

## New classes inventory (track completion)

| # | Class | Type | Phase | Status |
|---|--------|------|-------|--------|
| 1 | `ReportBloc<T>` + state/events | Bloc | 1 | [ ] |
| 2 | `DashboardNavCubit` | Cubit | 4B | [ ] |
| 3 | `DailyStatsCubit` | Cubit | 4B | [ ] |
| 4 | `ReceiptAllocationBloc` | Bloc | 4C | [ ] |
| 5 | `MastersSyncBloc` | Bloc | 4D | [ ] |
| 6 | `GpsCaptureBloc` | Bloc | 2 | [ ] |
| 7 | `CreateCustomerCubit` | Cubit | 3 | [ ] |
| 8 | `ListFilterCubit<T>` | Cubit | 2 | [ ] |
| 9 | `LineEditorCubit` | Cubit | 4G | [ ] |
| 10 | `RouteSelectionUiCubit` | Cubit | 4H | [ ] |
| 11 | `AsyncSearchBloc` | Bloc | 4J | [ ] |
| 12 | Invoice cart (existing `SalesInvoiceBloc`) | reuse | 5 | [ ] |
| 13 | `SalesReturnQuickCubit` | Cubit | 6 | [ ] |

---

## Files inventory (track conversion)

### Group A — Reports
- [ ] `item_sales_report_page.dart`
- [ ] `aging_receivables_report_page.dart`
- [ ] `stock_report_page.dart`
- [ ] `order_status_report_page.dart`
- [ ] `customerwise_returns_summary_report_page.dart`
- [ ] `itemwise_returns_summary_report_page.dart`
- [ ] `orders_summary_by_customer_report_page.dart`
- [ ] `itemwise_orders_summary_report_page.dart`
- [ ] `sales_summary_by_customer_item_report_page.dart`
- [ ] `sales_summary_by_customer_value_report_page.dart`
- [ ] `invoice_receipts_summary_report_page.dart`
- [ ] `expense_summary_report_page.dart`
- [ ] `transactions_summary_report_page.dart`

### Other plan files
- [ ] `dashboard_page.dart` (B)
- [ ] `receipt_payment_dialog.dart` (C)
- [ ] `masters_sync_page.dart` (D)
- [ ] `customer_selector_sheet.dart` (E)
- [ ] `create_customer_dialog.dart` (E)
- [ ] `item_search_sheet.dart` (F)
- [ ] `item_line_editor_dialog.dart` (G)
- [ ] `route_page.dart` (H)
- [ ] `invoice_flow_sheet.dart` (I)
- [ ] `async_search_widget.dart` (J)

### Gap (INCLUDE — designed)
- [ ] `sales_return_dialog.dart` → `SalesReturnQuickCubit` ([design](sales_return_dialog_design.md))

### Explicit non-targets
- [x] `voucher_pdf_bloc.dart` (false positive)
- [x] Do not add page blocs to global `app.dart` MultiBlocProvider

---

## Risk register (do not skip)

| Risk | Severity | Mitigation |
|------|----------|------------|
| Global `SalesInvoiceBloc` cart contamination | **Critical** | `ClearCart` on invoice sheet open; manual regression editor/order |
| Receipt focus-aware controller sync | High | Listener + `!hasFocus` before writing `.text` |
| Equatable + mutated lists (masters logs, allocations) | High | Always new collection instances |
| Masters bulk sync after dispose | Medium | isClosed / cancel subscription in `close()` |
| Create-customer / receipt submit no try/catch | Medium | Explicit failure states + submitting flags |
| Live open-invoice refresh clobbering manual allocations | Medium | Explicit product decision A/B |
| Async search stale results | Medium | Remove 500ms fake delay; cancel Timer |
| GPS permission vs service vs timeout | Medium | Distinct states; match permission_handler usage |
| `activeRouteId` after await | Medium | Inject before async gap |
| Aggregation pushed into generic ReportBloc | Medium | Keep pure per-page `buildReport` |
| Forgetting dashboard stats refresh call sites | Medium | Grep `_loadDailyStats` / `.then` until none |
| sales_return_dialog left behind | Low–Med | Task 0.4 decision before “done” |
| Over-scoping into app.dart globals | Low | Local providers only |

---

## Suggested PR slices (optional)

1. **PR1:** ReportBloc + all 13 reports + tests  
2. **PR2:** ListFilterCubit + GpsCaptureBloc + customer selector + item search  
3. **PR3:** CreateCustomerCubit + dialog  
4. **PR4:** ReceiptAllocationBloc  
5. **PR5:** MastersSyncBloc  
6. **PR6:** Dashboard cubits + LineEditor + RouteSelectionUi + AsyncSearch  
7. **PR7:** Invoice flow SalesInvoiceBloc reroute (+ hard regression)  
8. **PR8 (optional):** sales_return_dialog  

Each PR: analyze + tests + group manual checks from this doc.
