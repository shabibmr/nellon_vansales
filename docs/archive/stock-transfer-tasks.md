# Stock Transfer Architecture — Task List

> **ARCHIVED — all three candidates delivered.** Checkboxes below were never
> ticked during implementation; they were reconciled against the code on
> 2026-09-07 and are now accurate. Two candidates landed under different names
> than this plan proposed — noted per candidate.
>
> **One item was never done:** `CONTEXT.md` still does not exist. Three tasks
> below asked for it. Tracked in [README.md](./README.md) rather than here.

Derived from `stock-transfer-architecture-review.md`. Work top to bottom; finish each candidate (grilling + any resulting implementation) before starting the next.

## Candidate 1 — Narrow the `SalesRepository` seam for `StockTransferBloc` (Strong, do first)

**Landed as planned.** `StockTransferRepository` in `lib/domain/repositories/`,
impl in `lib/data/repositories/stock_transfer_repository_impl.dart`.
`SalesRepository` was subsequently deleted outright (see
[sales-repository-split-plan.md](./sales-repository-split-plan.md)), so the
"delegate from `SalesRepositoryImpl`" step became moot.

- [x] Run `/grilling` on Candidate 1: settle the seam's name (e.g. `StockTransferDataSource`), its exact method list (the 8 currently used: `getWarehouses`, `primaryWarehouseId`, `assignedWarehouseId`, `fetchRemoteItems`, `getItems`, `getLocalInvoices`, `saveLocalStockTransfer`, `enqueueSyncItem`), and where it lives (`domain/repositories/`) — settled as `StockTransferRepository`
- [x] Define the new interface and have `SalesRepositoryImpl` satisfy/delegate to it — separate `StockTransferRepositoryImpl`; no delegation, `SalesRepositoryImpl` is gone
- [x] Repoint `StockTransferBloc` to depend on the new seam instead of the full `SalesRepository` — `StockTransferBloc(stockTransferRepository: repo)`
- [x] Add a small test fake (8 methods) and write tests for the previously-untestable paths: `_onLoadIssueGrid`'s live/offline fallback, the stock ∪ demand union, `_resolveDefaultWarehouse`/`_resolveCurrentLocation` fallbacks, and all of `_onSubmitTransfer`'s validation + enqueue path — all covered in `test/stock_transfer_bloc_test.dart` (three validation gates, record+triggerSync success path, live flag, demand union, plus edit-mode and read-only guards this plan did not anticipate)
- [ ] Update `CONTEXT.md` with the new term (create the file if it doesn't exist yet) — **not done, file never created**
- [x] Run `flutter analyze` and `flutter test test/stock_transfer_bloc_test.dart`

## Candidate 2 — Shared `StockTransferGridScaffold` (Strong)

**Landed as `StockTransferEditorView`**, in the feature's own
`lib/ui/features/stock_transfer/views/` rather than `lib/ui/core/widgets/` —
it is used by exactly two pages in one feature, so it did not earn a place in
the shared core layer. Takes `isLoad` + `existingTransfer` instead of the
builder/label slots proposed here; both pages are now ~50-line wrappers whose
only job is `open()` route + bloc construction.

- [x] Run `/grilling` on Candidate 2: settle the scaffold's parameters (grid-body builder slot, header labels, footer button label/handler, banner slots for offline/no-warehouse states) — resolved to a single `isLoad` flag; `_Banner` is a private widget inside the view
- [x] Extract the scaffold into `lib/ui/core/widgets/` alongside `editor_footer.dart` / `dialog_scaffolding.dart` — extracted to `features/stock_transfer/views/stock_transfer_editor_view.dart` instead, see note above
- [x] Refactor `IssueToVanPage` to use the scaffold, keeping only `_buildGrid`/`_buildExtraQtyCell` and the "Add Item" sheet flow — page is now a thin wrapper; grid + add-item flow live in the shared view
- [x] Refactor `StockUnloadingPage` to use the scaffold, keeping only `_UnloadRow` — same; `_UnloadRow` folded into the shared row rendering
- [x] Resolve the `_extraControllers` text-sync note: move the "re-express entered qty in the new unit" rule out of the widget's `onChanged` and into the bloc (or an explicit row-cell widget contract) — unit/qty entry moved into `StockTransferQtyDialog` (Candidate 3), removing the inline controller-sync problem
- [ ] Update `CONTEXT.md` with the new term — **not done, file never created**
- [x] Run `flutter analyze` and `flutter test`

## Candidate 3 — Reuse/extend `SharedItemLineEditorDialog` (Worth exploring)

**Option (b) chosen.** `lib/ui/features/stock_transfer/widgets/stock_transfer_qty_dialog.dart`
is a sibling widget; its own doc comment records the reason for not broadening
the shared dialog — a transfer line has no rate or tax, so a quantity-only mode
would have meant threading "hide these fields" flags through the shared editor.

- [x] Run `/grilling` on Candidate 3: decide between (a) broadening `SharedItemLineEditorDialog` with a quantity-only mode, or (b) extracting a sibling quantity+unit widget next to `ItemLineUomSelector` — chose (b)
- [x] Implement the chosen approach — `StockTransferQtyDialog.show(...)`
- [x] Replace `IssueToVanPage._promptQuantity` with the reused/extended module — `_promptQuantity` no longer exists; both call sites go through `StockTransferQtyDialog.show`
- [ ] Update `CONTEXT.md` if a new term is introduced — **not done, file never created**
- [x] Run `flutter analyze` and `flutter test`
