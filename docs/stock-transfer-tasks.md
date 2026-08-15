# Stock Transfer Architecture — Task List

Derived from `stock-transfer-architecture-review.md`. Work top to bottom; finish each candidate (grilling + any resulting implementation) before starting the next.

## Candidate 1 — Narrow the `SalesRepository` seam for `StockTransferBloc` (Strong, do first)

- [ ] Run `/grilling` on Candidate 1: settle the seam's name (e.g. `StockTransferDataSource`), its exact method list (the 8 currently used: `getWarehouses`, `primaryWarehouseId`, `assignedWarehouseId`, `fetchRemoteItems`, `getItems`, `getLocalInvoices`, `saveLocalStockTransfer`, `enqueueSyncItem`), and where it lives (`domain/repositories/`)
- [ ] Define the new interface and have `SalesRepositoryImpl` satisfy/delegate to it
- [ ] Repoint `StockTransferBloc` to depend on the new seam instead of the full `SalesRepository`
- [ ] Add a small test fake (8 methods) and write tests for the previously-untestable paths: `_onLoadIssueGrid`'s live/offline fallback, the stock ∪ demand union, `_resolveDefaultWarehouse`/`_resolveCurrentLocation` fallbacks, and all of `_onSubmitTransfer`'s validation + enqueue path
- [ ] Update `CONTEXT.md` with the new term (create the file if it doesn't exist yet)
- [ ] Run `flutter analyze` and `flutter test test/stock_transfer_bloc_test.dart`

## Candidate 2 — Shared `StockTransferGridScaffold` (Strong)

- [ ] Run `/grilling` on Candidate 2: settle the scaffold's parameters (grid-body builder slot, header labels, footer button label/handler, banner slots for offline/no-warehouse states)
- [ ] Extract the scaffold into `lib/ui/core/widgets/` alongside `editor_footer.dart` / `dialog_scaffolding.dart`
- [ ] Refactor `IssueToVanPage` to use the scaffold, keeping only `_buildGrid`/`_buildExtraQtyCell` and the "Add Item" sheet flow
- [ ] Refactor `StockUnloadingPage` to use the scaffold, keeping only `_UnloadRow`
- [ ] Resolve the `_extraControllers` text-sync note: move the "re-express entered qty in the new unit" rule out of the widget's `onChanged` and into the bloc (or an explicit row-cell widget contract)
- [ ] Update `CONTEXT.md` with the new term
- [ ] Run `flutter analyze` and `flutter test`

## Candidate 3 — Reuse/extend `SharedItemLineEditorDialog` (Worth exploring)

- [ ] Run `/grilling` on Candidate 3: decide between (a) broadening `SharedItemLineEditorDialog` with a quantity-only mode, or (b) extracting a sibling quantity+unit widget next to `ItemLineUomSelector`
- [ ] Implement the chosen approach
- [ ] Replace `IssueToVanPage._promptQuantity` with the reused/extended module
- [ ] Update `CONTEXT.md` if a new term is introduced
- [ ] Run `flutter analyze` and `flutter test`
