# SalesRepository Split — Analysis & Plan

> **Status:** Research complete, 4 design decisions still open. No code written yet.
> **Prerequisite reading:** none — this document is self-contained.
> **Related:** [`stock-transfer-architecture-review.md`](./stock-transfer-architecture-review.md) (this work grew out of its Candidate 1).

---

## 1. Problem

`lib/domain/repositories/sales_repository.dart` is **280 lines, 51 members**. It is organised around its **data sources** (`HiveDatabaseService` — itself 1,530 lines — plus `ZohoApiClient`) rather than around domain concepts. Every feature that needed van-sales data added its methods here, because this was the one class that already had both dependencies wired.

The growth pattern is visible in the method list. Nearly every transaction type contributed the same quartet:

```
getLocalX()          → read from Hive
saveLocalX()         → write to Hive
fetchRemoteX(dates)  → pull from Zoho, merge into Hive
fetchXById()         → single-record read
```

Seven transaction types (invoices, orders, receipts, returns, expenses, cash closing, stock transfers) × ~4 methods ≈ **28 of the 51**. Add customers (8), items (4), routes (3), warehouses (3), and that is the whole file.

Of the 51 methods, **16 are literal one-liners** (`List<Item> getItems() => _dbService.getItems();`). Only ~17 do real work, and that work is almost always the same shape: call Zoho → map JSON to a model → merge into the Hive cache.

### This is measurably off-pattern for this codebase

| Interface | Lines | Methods |
|---|---|---|
| `AuthRepository` | 29 | 4 |
| `SalespersonRepository` | 38 | 4 |
| `ReportRepository` | 42 | 9 |
| `SyncRepository` | 45 | 7 |
| `VoucherPdfRepository` | 49 | 7 |
| `ThermalPrinterRepository` | 64 | 10 |
| **`SalesRepository`** | **280** | **51** |

4–10 methods is this project's own norm. `SalesRepository` is a 5× outlier. **Target every new repository at 4–10 methods.**

Note also that `ReportRepository` already carves off an adjacent slice (`fetchInvoices`, `fetchSalesOrders`, `fetchReceipts`, `fetchStockTransfers`, …). Per-concept splitting is an established pattern here — it was simply never applied to `SalesRepository`.

---

## 2. Measured cost

> These figures come from two exhaustive mapping passes over `lib/` and `test/`. **Do not re-derive them** — they are expensive and already verified.

**Blast radius**
- **56 files in `lib/`** reference `SalesRepository`
- **22 test files** fake it

**Test-suite cost**
- **20 hand-written fakes, ~2,634 lines total**
- No shared test helper exists (`test/helpers/`, `test/fakes/`, `test/support/`, `test/mocks/` — none of them)
- No `mocktail` or `mockito` in `pubspec.yaml` dev_dependencies — every fake is hand-typed
- Typical fake: **~168 lines to supply ~5 methods** of real behaviour → **~90% dead stub code**
- Drift already present: `fetchCustomerLedger` throws in most fakes but returns a real zeroed object in `cash_closing_cubit_test.dart`; `pushCustomerGpsRemote` is `async {}` in some and throws in others; `getLocalCashClosing` is missing entirely from `expense_editor_bloc_test.dart`

**Coupling hot spots**
- `enqueueSyncItem` — **13 call sites**, nearly always immediately after a `saveLocalX()`
- `getCustomers` — **15 call sites**

**Dead surface (zero consumers in `lib/`)**
`saveItems`, `getLocalCashClosing`, `getSyncQueue`, `getLocalStockTransfers`, `fetchRemoteStockTransfers`

**Free win:** stock-transfer methods are pure dead stubs in all 15 exhaustive fakes → **~120 lines deletable with zero behavioural risk**.

### Two fake styles (determines per-file migration cost)

| Style | Files | Mechanism | Migration cost |
|---|---|---|---|
| **A** | 15 | Exhaustive `implements SalesRepository` — all ~51 members hand-written, ~45 inert | **High** — delete and re-split across N narrow fakes |
| **B** | 6 | `implements SalesRepository` + hand-rolled `noSuchMethod` escape hatch; only 2–4 members declared | **Low** — retarget the `implements` clause |

Two further files (`customer_detail_resolve_test.dart`, `unit_conversion_resolve_test.dart`) use the **real** `SalesRepositoryImpl` and fake the layers below it — constructor-name changes only.

---

## 3. Pre-existing bug — verify separately

`integration_test/app_test.dart` appears **stale and non-compiling**, independent of this refactor.

Its `FakeSalesRepository` omits ~10 required members (`getWarehouses`, `assignedWarehouseId`, `primaryWarehouseId`, `fetchRemoteItems`, `getOrganization`, `hasPendingCashClosingForToday`, `fetchExpenseById`, `fetchCustomerLedger`, `getCustomerById`, `pushCustomerGpsRemote`) while declaring no `noSuchMethod`. It also uses outdated signatures for `fetchInvoiceById`, `fetchReceiptById`, `fetchSalesReturnById`, and `fetchRemoteOrder` — all of which have since gained named parameters (`{bool forceRemote, bool allowOfflineFallback}`).

It has almost certainly dropped out of the CI path. **Confirm this before assuming the split broke it.**

---

## 4. Proposed split — 9 repositories

| New repository | Methods | Members |
|---|---|---|
| `CustomerRepository` | 9 | `getCustomers`, `saveCustomers`, `getCustomerById`, `updateCustomerGps`, `updateCustomerContactFields`, `resolveCustomerDetails`, `pushCustomerGpsRemote`, `pushCustomerContactFieldsRemote`, `fetchCustomerLedger` |
| `SessionRepository` | 9 | `getRoutes`, `activeRouteId`, `setActiveRouteId`, `getWarehouses`, `assignedWarehouseId`, `primaryWarehouseId`, `getOrganization`, `hasPendingCashClosingForToday`, `saveLocalCashClosing` |
| `InvoiceRepository` | 6 | `getLocalInvoices`, `saveLocalInvoice`, `fetchInvoiceById`, `fetchRemoteInvoices`, `getOpenInvoices`, `fetchRemoteOpenInvoices` |
| `SalesOrderRepository` | 5 | `getLocalOrders`, `saveLocalOrder`, `enqueueSalesOrder`, `fetchRemoteOrders`, `fetchRemoteOrder` |
| `StockTransferRepository` | 5 | reshaped — see §5 |
| `ReceiptRepository` | 4 | `getLocalReceipts`, `saveLocalReceipt`, `fetchReceiptById`, `fetchRemoteReceipts` |
| `SalesReturnRepository` | 4 | `getLocalReturns`, `saveLocalReturn`, `fetchSalesReturnById`, `fetchRemoteReturns` |
| `ExpenseRepository` | 4 | `getLocalExpenses`, `saveLocalExpense`, `fetchExpenseById`, `fetchRemoteExpenses` |
| `ItemRepository` | 3 | `getItems`, `resolveItemUnitConversions`, `fetchRemoteItems` |

**Structure:** all interfaces flat in `lib/domain/repositories/`, matching existing convention. Each gets its own `XRepositoryImpl` in `lib/data/repositories/`, taking the same `dbService` + `apiClient` constructor parameters every existing impl already takes, and wired independently in `lib/data/services/injection.dart` — exactly how `SyncRepositoryImpl`, `SalespersonRepositoryImpl`, and `ReportRepositoryImpl` are wired today.

---

## 5. Decisions already settled

These were worked through in a grilling session. **Do not reopen without new information.**

1. **Standalone interfaces — not subsetting, mixins, or wrapper adapters.** No interface in this codebase extends another; all seven existing repository interfaces are flat `abstract class` declarations.
2. **`XRepository` naming.** Matches the established `FakeXRepository implements XRepository` test convention.
3. **Interfaces live flat in `lib/domain/repositories/`.** No feature-local repository interfaces exist anywhere in `lib/ui/features/`.
4. **Reshape around real call patterns rather than copying the existing signatures verbatim.**
5. **Separate `XRepositoryImpl` classes — do NOT have `SalesRepositoryImpl` implement additional interfaces.** It is already 716 lines / 51 methods; adding hats to it works directly against the goal of this refactor.
6. **`SyncRepository` stays untouched.** At 7 methods it is already narrow and appropriately deep for its callers.
7. **The stock-transfer history/list screen is out of scope.** It lives in `lib/ui/features/reports/` (`StockTransferHistoryReportPage` + `StockTransferHistoryAggregator`), uses different methods (`getLocalStockTransfers`/`fetchRemoteStockTransfers` — both dead), and its aggregator is already a pure, dependency-free static class with no testability gap.

### Agreed `StockTransferRepository` shape

```dart
abstract class StockTransferRepository {
  /// Current-location item stock, preferring a live Zoho fetch and falling
  /// back to the local cache on failure.
  Future<({List<Item> items, bool live})> loadCurrentLocationItems();

  /// Local item cache only (Stock Unloading's source of truth, and the
  /// backfill source for demand items missing from [loadCurrentLocationItems]).
  List<Item> getItems();

  /// Invoiced quantity per item id for [asOf] (defaults to today), scoped
  /// to the current location.
  Map<String, double> getTodaysInvoicedQuantities({DateTime? asOf});

  /// Both ends of a transfer: the org's default warehouse and the van's
  /// current location, each resolved with its fallback rule applied.
  ({Warehouse defaultWarehouse, Warehouse currentLocation}) resolveTransferLocations();

  /// Persists [transfer] locally and enqueues it for sync.
  Future<void> recordStockTransfer(StockTransfer transfer);
}
```

**Why 5 methods rather than the 8 raw ones `StockTransferBloc` calls today:**
- `resolveTransferLocations()` absorbs `getWarehouses` + `primaryWarehouseId` + `assignedWarehouseId` *and* both private fallback helpers (`_resolveDefaultWarehouse`, `_resolveCurrentLocation`).
- `_onSubmitTransfer`'s standalone `assignedWarehouseId` null/empty check collapses to `currentLocation.id.isEmpty`, because `_resolveCurrentLocation()` already guarantees `currentLocation.id == (assignedWarehouseId ?? '')`.
- `loadCurrentLocationItems()` absorbs the try/catch live-fetch-then-cache-fallback branch and the `isLiveData` flag.
- `recordStockTransfer()` absorbs `saveLocalStockTransfer` + `enqueueSyncItem`.

**Bonus fix this enables:** `lib/ui/features/stock_transfer/bloc/stock_transfer_bloc.dart` currently imports `data/models/sync_queue_item.dart` and `data/models/stock_transfer_model.dart` directly and builds the `SyncQueueItem` payload itself — a violation of the project's own rule (`CLAUDE.md`: *"`ui/` depends on `domain/` interfaces only"*). Moving `SyncQueueItem` construction into `recordStockTransfer()` removes both imports.

**Test coverage this unlocks** (currently `test/stock_transfer_bloc_test.dart` exercises only pure functions — `StockTransferRow` math, `StockTransferState.transferQtyFor`, `buildIssueToVanRows` — and not one event handler):
- `_onSubmitTransfer`'s three validation gates: empty lines, unconfigured primary warehouse, unresolved van location
- The save + enqueue + `triggerSync` success path
- `_onLoadIssueGrid`'s live-fetch-failure → cache-fallback branch and `isLiveData` flag
- The stock ∪ demand union (a sold-out item with demand must still appear)
- Warehouse-resolution fallbacks (primary-flag lookup → first warehouse; assigned-id lookup → placeholder)

For repository-impl-level tests, follow the existing pattern in `test/sync_repository_record_count_test.dart`: subclass `HiveDatabaseService` / `ZohoApiClient` and override only the methods needed — no Hive test harness required.

---

## 6. OPEN QUESTIONS — answer before writing code

**These are genuinely undecided.** Put them to the user first.

### Q1. Where does `enqueueSyncItem` go?
13 call sites, nearly always immediately after a `saveLocalX()`.

- **(a) Bundle into each save** — `saveLocalInvoice` + `enqueueSyncItem` → one `recordInvoice(invoice)`. Consistent with the already-agreed `recordStockTransfer`; eliminates the hottest coupling point; moves `SyncQueueItem` construction out of the UI layer everywhere. Touches the most call sites.
- **(b) Move to `SyncRepository`** — it already owns `getSyncQueue` and `triggerSync`. Smaller diff, but blocs still hand-build `SyncQueueItem`.
- **(c) Duplicate on each of the 9 repositories** — no extra injected dependency, but the same method appears 9 times.

### Q2. How does `DailyStatsCubit` get its data?
`lib/ui/features/dashboard/cubit/daily_stats_cubit.dart` reads five concepts at once: `getLocalInvoices`, `getLocalReceipts`, `getLocalExpenses`, `getLocalReturns`, `getLocalOrders`.

- Inject all five repositories (honest, verbose; its test needs five ~10-line fakes instead of today's 131-line one)
- A dedicated `DailyStatsRepository` exposing just today's totals (cleanest call site, one fake; but a 10th repository overlapping the other five)
- A thin cross-concept read facade over the local caches (risks becoming a new mini-god-object)

### Q3. What happens to the 5 dead methods?
`saveItems`, `getLocalCashClosing`, `getSyncQueue`, `getLocalStockTransfers`, `fetchRemoteStockTransfers`.

- Delete outright — note `fetchRemoteStockTransfers`/`getLocalStockTransfers` overlap `ReportRepository.fetchStockTransfers`, which is the live path, so nothing is lost
- Carry all 5 forward into whichever new repository they belong to
- Judge case-by-case during implementation and report what was dropped

⚠️ The consumer map covered `lib/` only. **Check `test/` usage before deleting each one.**

### Q4. Migration strategy?
56 `lib/` files + 22 test files affected.

- **Incremental** — keep `SalesRepository` alive as a temporary delegating facade, migrate consumers concept-by-concept over several commits, delete the facade last. Every step compiles and tests stay green.
- **Big bang** — split, rewrite everything, delete `SalesRepository` in one commit. Fastest to a clean end state; nothing compiles until done, and mistakes are hard to bisect.
- **Pilot first** — do only the `StockTransferRepository` carve-out, verify the pattern end-to-end, then re-plan the remaining 8.

---

## 7. Verification

Whatever gets implemented must end with:

```bash
flutter analyze     # clean
flutter test        # green
```

Plus: assess `integration_test/app_test.dart` (§3) **separately** — it was already suspect beforehand and should not be treated as a regression from this work.
