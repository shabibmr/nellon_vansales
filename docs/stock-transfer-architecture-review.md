# Architecture review: `lib/ui/features/stock_transfer/`

## Context

Analysis via `/improve-codebase-architecture`, scoped to `lib/ui/features/stock_transfer/` per request. This is a small feature (3 files: `bloc/stock_transfer_bloc.dart`, `views/issue_to_van_page.dart`, `views/stock_unloading_page.dart`, ~1,388 lines total) that drives both the Issue-to-Van and Stock-Unloading planning grids and submits them as Zoho Transfer Orders. No `CONTEXT.md` or `docs/adr/` exist yet in this repo, so there's no prior domain vocabulary or ADRs to reconcile against.

Three deepening candidates surfaced, grounded in code read this session: `stock_transfer_bloc.dart`, both view files, `domain/repositories/sales_repository.dart`, `domain/repositories/sync_repository.dart`, `test/stock_transfer_bloc_test.dart`, and `lib/ui/core/widgets/item_line_editor_dialog.dart`.

---

## Candidate 1 — `SalesRepository` is a god-interface hiding a testability gap in `StockTransferBloc`

**Recommendation: Strong**

**Files:** `lib/ui/features/stock_transfer/bloc/stock_transfer_bloc.dart`, `lib/domain/repositories/sales_repository.dart`, `test/stock_transfer_bloc_test.dart`

**Problem**

`StockTransferBloc` depends on `SalesRepository`, a **shallow module for this caller**: the interface has 30+ methods spanning customers, invoices, orders, receipts, returns, expenses, cash closing, ledger, and GPS push — but `StockTransferBloc` only ever calls 8 of them (`getWarehouses`, `primaryWarehouseId`, `assignedWarehouseId`, `fetchRemoteItems`, `getItems`, `getLocalInvoices`, `saveLocalStockTransfer`, `enqueueSyncItem`). Contrast with `SyncRepository` (9 members total, used almost entirely by the bloc) — that one is appropriately deep for its callers; `SalesRepository` is not.

The consequence is visible in `test/stock_transfer_bloc_test.dart` today: all 172 lines test **pure, standalone functions** that happen to live in the bloc file — `StockTransferRow` getters (`subtotal`, `grandTotal`), `StockTransferState.transferQtyFor`, and the free function `buildIssueToVanRows`. Not one test drives the bloc's actual event handlers (`_onLoadIssueGrid`, `_onSubmitTransfer`, `_onUpdateExtraQty`, …). That's the "pure functions extracted for testability, but the real bugs hide in how they're called" pattern — there's no **locality** between the tested math and the untested orchestration that calls it.

Untested right now, because faking `SalesRepository` means standing up (or mocking) 30 unrelated methods:
- The live/offline fallback in `_loadIssueGridWithQtyMap` (`fetchRemoteItems` throws → falls back to `getItems()`, flips `isLiveData`)
- The stock ∪ demand union logic (items with demand but zero cached stock still need to resolve to *something* displayable)
- `_resolveDefaultWarehouse` / `_resolveCurrentLocation` fallback chains (primary-flag lookup, "Default Warehouse" placeholder)
- All of `_onSubmitTransfer`'s validation gates (empty lines, unconfigured primary warehouse, unresolved van location) and the sync-queue enqueue path — this is the transactional write path (`saveLocalStockTransfer` + `enqueueSyncItem` + `triggerSync`) that CLAUDE.md flags as important (stock transfers are mock-gated in Zoho sync, so local correctness is the only real guarantee)

**Deletion test:** delete `StockTransferBloc`'s dependency on the full `SalesRepository` and replace it with only the 8 methods it uses — nothing about the bloc's own behavior needs to change. The other 20+ methods were never exercised. That's a pass-through dependency, not an earned one.

**Solution**

Carve a narrow seam: a small interface (e.g. `StockTransferDataSource`, name to be settled in `/grilling`) exposing exactly the 8 operations `StockTransferBloc` needs, expressed in terms the bloc actually cares about (warehouses, current-location items, today's invoiced quantities, save+enqueue transfer). `SalesRepositoryImpl` implements or delegates to it in production. Tests get a second, real adapter — a small fake with 8 methods instead of 30 — making `_onSubmitTransfer`, `_onLoadIssueGrid`'s fallback branch, and the warehouse-resolution fallbacks finally testable without dragging in customer/invoice/expense/ledger concerns. Two adapters (prod delegate + test fake) make this a real seam, not a hypothetical one.

**Benefits**

- **Leverage**: one small interface pays back at every test call site instead of forcing 30-method fakes.
- **Locality**: transfer-submission bugs (the actual money/stock-moving logic) become testable at the seam where they live, not scattered across an untestable event handler.
- **Depth**: `StockTransferBloc`'s effective interface shrinks to what it actually uses — the caller-facing contract stops implying dependencies on customer ledgers and GPS push that have nothing to do with stock transfers.

**Before / After**

```
Before:                                   After:
StockTransferBloc                         StockTransferBloc
      │ depends on (8 of 30 methods)            │ depends on (all 8 methods)
      ▼                                          ▼
SalesRepository (30+ methods:              StockTransferDataSource (8 methods)
  customers, invoices, orders,                   │           ▲
  receipts, returns, expenses,                   │           │
  cash closing, ledger, GPS,             delegates│      fakes│
  stock transfers, warehouses...)                 ▼           │
                                          SalesRepositoryImpl  StockTransferFake
                                          (prod)                (test — 8 methods)

Test today: only pure functions reachable.
Test after: _onSubmitTransfer, _onLoadIssueGrid fallback,
            warehouse resolution — all reachable through the fake.
```

---

## Candidate 2 — `IssueToVanPage` and `StockUnloadingPage` duplicate an entire page shell

**Recommendation: Strong**

**Files:** `lib/ui/features/stock_transfer/views/issue_to_van_page.dart`, `lib/ui/features/stock_transfer/views/stock_unloading_page.dart`

**Problem**

Both pages independently reimplement the same shallow shell around the grid that actually differs between them:

- An identical `BlocConsumer` listener: success → snackbar + `ClearMessages` + `Navigator.pop`; error → snackbar + `ClearMessages` (`issue_to_van_page.dart:179-191`, `stock_unloading_page.dart:53-65` — byte-for-byte the same logic, copy-pasted)
- A near-identical route header bar (from/to labels either side of an arrow icon) — `_RouteHeader` in `issue_to_van_page.dart:483-574` vs. the inline `Row`/`Container` in `stock_unloading_page.dart:71-119`
- A per-row `TextEditingController` map with matching `_controllerFor`/`dispose` boilerplate in both `State` classes
- Both end in an `EditorFooter` with a totals row + submit button gated on `isLoading`/`totalTransferQty`

The only things that actually differ are the grid body (a `Table` for Issue-to-Van vs. a `ListView.separated` of `_UnloadRow` cards for Unloading) and a couple of page-specific strings/flags (button label, "Add Item" affordance, the offline/no-warehouse banners).

**Deletion test:** delete `IssueToVanPage` and its BlocConsumer-listener/header/footer wiring — that exact logic reappears verbatim in `StockUnloadingPage`. It didn't vanish; it was duplicated. That's the signature of an un-extracted seam, not incidental similarity.

**Solution**

Extract a shared `StockTransferGridScaffold`-style widget (name TBD in `/grilling`) into `lib/ui/core/widgets/` — the same place `editor_footer.dart` and `dialog_scaffolding.dart` already live for this exact purpose (CLAUDE.md: "Shared UI Layer... reuse these before writing per-feature variants"). It would own: the `BlocConsumer` + success/error listener, the header bar (from/to labels + optional date), the loading indicator, the empty state, and the `EditorFooter` wiring — taking the grid body and page-specific labels as parameters. Each page shrinks to just its grid-rendering logic (`_buildGrid`/`_buildExtraQtyCell` for Issue-to-Van, `_UnloadRow` for Unloading) plus whatever's genuinely page-specific (the "Add Item" sheet flow, the primary-warehouse-missing banner).

**Benefits**

- **Locality**: the success/error/pop flow — a real behavioral contract about what happens after a transfer submits — lives in one place. Today, fixing a bug in it (or adding a new post-submit step) means remembering to patch two files identically.
- **Leverage**: a bug fix or a new grid mode (a third transfer direction, say) gets the shell for free instead of a third copy-paste.
- **Depth**: each page's remaining code is 100% about *what makes this grid different*, not shell wiring — a much smaller, more honest interface for a reader (or an AI agent) to reason about.

**Note (fold into the same grilling conversation, not a separate candidate):** `IssueToVanPage._buildExtraQtyCell`'s unit-dropdown `onChanged` (`issue_to_van_page.dart:369-383`) reaches directly into `_extraControllers[row.item.id]?.text` to re-express the quantity after firing `UpdateRowUnit` — a business rule ("re-express entered qty in the new unit") implemented in the widget layer even though all other quantity math lives in the bloc. Worth resolving as part of whatever shell/row-cell extraction comes out of this candidate.

**Before / After**

```
Before:                                    After:
IssueToVanPage          StockUnloadingPage      StockTransferGridScaffold
  BlocConsumer             BlocConsumer            BlocConsumer + listener
  listener (dup)           listener (dup)          header bar
  header (_RouteHeader)    header (inline)         loading / empty state
  grid: Table              grid: ListView          EditorFooter
  EditorFooter             EditorFooter                 │  builder slot
  (575 lines)               (253 lines)                 ▼
                                              IssueToVanPage        StockUnloadingPage
                                                just _buildGrid       just _UnloadRow
                                                + Add Item sheet      (page-specific only)
```

---

## Candidate 3 — `IssueToVanPage._promptQuantity` reinvents `SharedItemLineEditorDialog`

**Recommendation: Worth exploring**

**Files:** `lib/ui/features/stock_transfer/views/issue_to_van_page.dart` (`_promptQuantity`, lines 87-166), `lib/ui/core/widgets/item_line_editor_dialog.dart`

**Problem**

`_promptQuantity` hand-rolls an ~80-line `StatefulBuilder`-backed `AlertDialog`: a quantity `TextField` with decimal-precision `inputFormatters` driven by `item.conversionFor(uom)?.quantityDecimalPlaces`, plus an optional unit dropdown built from `item.uom` + `item.unitConversions`. That's the same responsibility — quantity entry with unit-aware precision and conversion — that `SharedItemLineEditorDialog` (+ `LineEditorCubit`, `ItemLineUomSelector`) already owns as a deep module used elsewhere for sales order / invoice line entry. The stock-transfer version is a shallower one-off: no rate/discount, no stock-cap validation, and it duplicates the unit-options-building expression (`[item.uom, ...item.unitConversions.map(...)]`) that also appears three separate times across `issue_to_van_page.dart` itself (`_promptQuantity`, `_buildExtraQtyCell`) as well as inside `item_line_editor_dialog.dart`.

**Deletion test:** ambiguous, which is why this is "Worth exploring" rather than "Strong" — deleting `_promptQuantity` wouldn't obviously make `SharedItemLineEditorDialog` reusable as-is, since that dialog currently always renders rate + discount fields, which the stock-transfer "Add Item" flow doesn't want. The duplication is real, but so is a genuine interface mismatch that needs resolving, not just a copy-paste to undo.

**Solution direction (to sharpen in `/grilling`, not decided here)**

Two shapes worth weighing against each other:
1. Broaden `SharedItemLineEditorDialog` with a "quantity-only" mode (hide rate/discount) so stock transfer's Add-Item flow reuses the existing deep module outright.
2. Extract just the quantity+uom sub-piece as its own small shared prompt (`ItemLineUomSelector` already exists as a building block; a sibling "quantity-with-unit" widget could sit next to it), leaving `SharedItemLineEditorDialog` untouched.

Option 1 raises `SharedItemLineEditorDialog`'s interface complexity (a mode flag) to lower call-site duplication; option 2 keeps that dialog's interface stable but adds a new small module. This is exactly the kind of trade-off `/grilling` is for.

**Benefits (if pursued)**

- **Leverage**: one unit-precision-and-conversion implementation instead of the pattern appearing independently in the sales-order/invoice dialog and the stock-transfer dialog.
- **Locality**: a future change to unit-conversion display rules (e.g. new decimal-precision policy) touches one module instead of needing a grep across features to find every hand-rolled copy.

---

## Top recommendation

**Start with Candidate 1** (the `SalesRepository` god-interface). It's the highest-leverage fix: it directly explains *why* `_onSubmitTransfer` — the code path that actually moves stock and enqueues a sync item — has zero test coverage today, and CLAUDE.md's own description of the sync system ("customers must sync before invoices," mock-gated transaction flags) signals this is exactly the kind of local-correctness-is-the-only-guarantee code that most needs a working test seam. It's also the least visually/behaviorally risky of the three — it's a pure dependency-seam change, no UI or user-facing behavior moves.

Candidate 2 (shared grid scaffold) is a close second and has no real trade-off to grill (unlike Candidate 3) — it's a clean, low-risk extraction with codebase precedent (`editor_footer.dart`, `dialog_scaffolding.dart`) already established as the "reuse before writing per-feature variants" pattern. Good next pick.

Candidate 3 is genuinely speculative until `/grilling` resolves whether to broaden `SharedItemLineEditorDialog` or extract a sibling widget — worth a look, but pick it up after 1 and 2.

---

## Decision & current status

User selected **all three candidates, in the recommended order** (1 → 2 → 3), each as its own grilling session. See `stock-transfer-tasks.md` for the task list.

### Candidate 1 — escalated, tracked elsewhere

Candidate 1 was grilled and **widened materially**. The investigation confirmed the diagnosis but showed the problem is not specific to stock transfer: `SalesRepository` is a 51-method god-interface with **56 consuming files in `lib/`** and **20 hand-written test fakes totalling ~2,634 lines (~90% dead stubs)**. Every other repository interface in this codebase is 4–10 methods.

The user chose to fix the root cause rather than one symptom. That work is now planned as a full 9-repository split:

➡️ **[`sales-repository-split-plan.md`](./sales-repository-split-plan.md)** — full analysis, the proposed split, settled decisions, and 4 open questions.

The `StockTransferRepository` carve-out described in Candidate 1 survives intact inside that plan (§5), including its agreed 5-method reshaped interface.

### Candidates 2 and 3 — unchanged, still pending

Both remain exactly as written above. Neither has been grilled yet, and neither depends on the outcome of the `SalesRepository` split — Candidate 2 is a widget-layer extraction and Candidate 3 is a dialog-reuse question.
