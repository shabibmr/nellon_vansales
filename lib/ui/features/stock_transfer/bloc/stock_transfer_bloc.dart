// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/stock_transfer.dart';
import '../../../../domain/models/submit_result.dart';
import '../../../../domain/models/warehouse.dart';
import '../../../../domain/repositories/stock_transfer_repository.dart';
import '../../../core/utils/error_mapper.dart';

// --- Row model ---

/// A single row of the stock-transfer planning grid.
///
/// For [StockTransferDirection.load] (Issue to Van): [currentStock] is Col 1,
/// [invoiceQty] is Col 2, [subtotal] is Col 3, [extraQty] is the editable
/// Col 4, [grandTotal] is Col 5, and [transferQty] (= invoiceQty + extraQty)
/// is the quantity that actually moves — Col 1 is already physically on the
/// van, so it is excluded from the transfer.
///
/// For [StockTransferDirection.unload] (Stock Unloading): [currentStock] is
/// the van's balance, [extraQty] is the editable transfer quantity (defaults
/// to the full balance, capped at it), and [transferQty] is just [extraQty].
/// All quantities ([currentStock], [invoiceQty], [extraQty]) are held in the
/// item's **base unit**; [uom]/[conversionRate] only describe the unit the
/// editable quantity is entered/displayed in (multi-UOM support).
class StockTransferRow extends Equatable {
  final Item item;
  final double currentStock;
  final double invoiceQty;
  final double extraQty;

  /// Unit the editable quantity is entered in. Empty = the item's base unit.
  final String uom;

  /// Base-unit multiplier of [uom] (1.0 for the base unit).
  final double conversionRate;

  const StockTransferRow({
    required this.item,
    required this.currentStock,
    this.invoiceQty = 0,
    this.extraQty = 0,
    this.uom = '',
    this.conversionRate = 1.0,
  });

  /// Effective display unit — row override, else the item master unit.
  String get displayUom => uom.isNotEmpty ? uom : item.uom;

  /// The editable quantity expressed in the selected unit
  /// (e.g. base 50 kg shown as 2 when the unit is "25 Kg Bag").
  double get extraQtyEntered =>
      conversionRate > 0 ? extraQty / conversionRate : extraQty;

  /// Col 3 — current stock plus today's invoiced quantity.
  double get subtotal => currentStock + invoiceQty;

  /// Col 5 — resulting van stock after the transfer completes.
  double get grandTotal => subtotal + extraQty;

  StockTransferRow copyWith({
    Item? item,
    double? currentStock,
    double? invoiceQty,
    double? extraQty,
    String? uom,
    double? conversionRate,
  }) {
    return StockTransferRow(
      item: item ?? this.item,
      currentStock: currentStock ?? this.currentStock,
      invoiceQty: invoiceQty ?? this.invoiceQty,
      extraQty: extraQty ?? this.extraQty,
      uom: uom ?? this.uom,
      conversionRate: conversionRate ?? this.conversionRate,
    );
  }

  @override
  List<Object?> get props =>
      [item, currentStock, invoiceQty, extraQty, uom, conversionRate];
}

/// Issue-to-Van planning rows: skip zero-stock items unless they have
/// invoice/demand quantity that still needs to be transferred.
List<StockTransferRow> buildIssueToVanRows(
  Iterable<Item> items,
  Map<String, double> qtyByItemId,
) {
  return [
    for (final item in items)
      if (item.stock > 0 || (qtyByItemId[item.id] ?? 0) > 0)
        StockTransferRow(
          item: item,
          currentStock: item.stock,
          invoiceQty: qtyByItemId[item.id] ?? 0,
        ),
  ]..sort((a, b) => a.item.name.compareTo(b.item.name));
}

// --- Events ---

abstract class StockTransferEvent extends Equatable {
  const StockTransferEvent();
  @override
  List<Object?> get props => [];
}

/// Loads the Issue-to-Van planning grid (warehouse → current location).
class LoadIssueGrid extends StockTransferEvent {}

/// Loads Issue-to-Van prefilled with order demand in the invoiceQty column.
///
/// [demandByItemId] maps item id → total quantity needed (e.g. from shipment
/// orders Items tab). Merges with live van stock; demand items missing from
/// stock still appear so they can be transferred.
class LoadIssueGridWithDemand extends StockTransferEvent {
  final Map<String, double> demandByItemId;
  const LoadIssueGridWithDemand(this.demandByItemId);

  @override
  List<Object?> get props => [demandByItemId];
}

/// Loads the Stock-Unloading grid (current location → warehouse).
class LoadUnloadGrid extends StockTransferEvent {}

/// Re-opens an existing Issue-to-Van transfer for viewing/editing: builds the
/// same current-stock grid as [LoadIssueGrid], but prefills each row's
/// editable quantity from [transfer]'s own lines instead of starting at 0.
/// Editable only while [transfer.status] is `draft`; read-only otherwise.
class LoadIssueGridForEdit extends StockTransferEvent {
  final StockTransfer transfer;
  const LoadIssueGridForEdit(this.transfer);

  @override
  List<Object?> get props => [transfer];
}

/// Re-opens an existing Stock-Unloading transfer for viewing/editing: builds
/// the same van-stock grid as [LoadUnloadGrid], but prefills each row's
/// editable quantity from [transfer]'s own lines instead of defaulting to the
/// full balance. Editable only while [transfer.status] is `draft`; read-only
/// otherwise.
class LoadUnloadGridForEdit extends StockTransferEvent {
  final StockTransfer transfer;
  const LoadUnloadGridForEdit(this.transfer);

  @override
  List<Object?> get props => [transfer];
}

/// Updates the editable quantity (Col 4 for load; transfer qty for unload)
/// for an existing row. [quantity] is expressed in the row's currently
/// selected unit; the handler converts it to base units.
class UpdateExtraQty extends StockTransferEvent {
  final String itemId;
  final double quantity;
  const UpdateExtraQty({required this.itemId, required this.quantity});

  @override
  List<Object?> get props => [itemId, quantity];
}

/// Switches the unit the row's editable quantity is entered in (multi-UOM).
class UpdateRowUnit extends StockTransferEvent {
  final String itemId;
  final String uom;
  final double conversionRate;
  const UpdateRowUnit({
    required this.itemId,
    required this.uom,
    required this.conversionRate,
  });

  @override
  List<Object?> get props => [itemId, uom, conversionRate];
}

/// Adds a new item to the grid (not present in Col 1/Col 2) with an initial
/// extra quantity, entered in [uom] ([conversionRate] converts to base).
class AddExtraItem extends StockTransferEvent {
  final Item item;
  final double quantity;
  final String uom;
  final double conversionRate;
  const AddExtraItem({
    required this.item,
    required this.quantity,
    this.uom = '',
    this.conversionRate = 1.0,
  });

  @override
  List<Object?> get props => [item, quantity, uom, conversionRate];
}

/// Drops a row entirely from the grid.
class RemoveRow extends StockTransferEvent {
  final String itemId;
  const RemoveRow(this.itemId);

  @override
  List<Object?> get props => [itemId];
}

/// Submits the current grid as a stock transfer.
class SubmitTransfer extends StockTransferEvent {
  final String notes;
  const SubmitTransfer({this.notes = ''});

  @override
  List<Object?> get props => [notes];
}

/// Clears success/failure notifications from the state.
class ClearMessages extends StockTransferEvent {}

// --- State ---

class StockTransferState extends Equatable {
  final StockTransferDirection direction;
  final List<StockTransferRow> rows;
  final Warehouse defaultWarehouse;
  final Warehouse currentLocation;
  final bool isLoading;
  final bool isLiveData;
  final String? errorMessage;
  final String? successMessage;

  /// Local id of the transfer being viewed/edited, or null when planning a
  /// brand-new transfer.
  final String? editingTransferId;

  /// The transfer's permanent Zoho `transfer_order_id` — required to submit
  /// an update. Null for a brand-new transfer or one never yet synced.
  final String? editingZohoTransferId;

  /// The transfer's existing voucher reference (e.g. `TO-00012`), preserved
  /// across an update so the local record doesn't lose its display number.
  final String? editingTransferNumber;

  /// The transfer's original issue date, preserved across an update so
  /// re-saving a draft doesn't silently bump its recorded date to today.
  final DateTime? editingTransferDate;

  /// Zoho's transfer-order workflow status (`draft`, `transferred`, ...) for
  /// the transfer being viewed/edited. Meaningless for a brand-new transfer
  /// (defaults to `draft`, matching a transfer that hasn't reached Zoho yet).
  final String status;

  const StockTransferState({
    this.direction = StockTransferDirection.load,
    this.rows = const [],
    this.defaultWarehouse = const Warehouse(id: '', name: 'Default Warehouse', address: ''),
    this.currentLocation = const Warehouse(id: '', name: 'Current Location', address: ''),
    this.isLoading = false,
    this.isLiveData = false,
    this.errorMessage,
    this.successMessage,
    this.editingTransferId,
    this.editingZohoTransferId,
    this.editingTransferNumber,
    this.editingTransferDate,
    this.status = 'draft',
  });

  /// Quantity that actually transfers for [row] (base units), depending on [direction].
  double transferQtyFor(StockTransferRow row) {
    return direction == StockTransferDirection.load
        ? row.invoiceQty + row.extraQty
        : row.extraQty;
  }

  /// Sum of [transferQtyFor] across all rows (base units).
  double get totalTransferQty =>
      rows.fold(0.0, (sum, row) => sum + transferQtyFor(row));

  /// Whether an existing transfer (rather than a brand-new one) is loaded.
  bool get isEditingExisting => editingTransferId != null;

  /// Locked to view-only: an existing transfer whose Zoho status has moved
  /// past `draft`. A brand-new transfer is never read-only.
  bool get isReadOnly => isEditingExisting && status != 'draft';

  StockTransferState copyWith({
    StockTransferDirection? direction,
    List<StockTransferRow>? rows,
    Warehouse? defaultWarehouse,
    Warehouse? currentLocation,
    bool? isLoading,
    bool? isLiveData,
    String? errorMessage,
    String? successMessage,
    String? editingTransferId,
    bool clearEditingTransferId = false,
    String? editingZohoTransferId,
    bool clearEditingZohoTransferId = false,
    String? editingTransferNumber,
    bool clearEditingTransferNumber = false,
    DateTime? editingTransferDate,
    bool clearEditingTransferDate = false,
    String? status,
  }) {
    return StockTransferState(
      direction: direction ?? this.direction,
      rows: rows ?? this.rows,
      defaultWarehouse: defaultWarehouse ?? this.defaultWarehouse,
      currentLocation: currentLocation ?? this.currentLocation,
      isLoading: isLoading ?? this.isLoading,
      isLiveData: isLiveData ?? this.isLiveData,
      errorMessage: errorMessage,
      successMessage: successMessage,
      editingTransferId: clearEditingTransferId
          ? null
          : (editingTransferId ?? this.editingTransferId),
      editingZohoTransferId: clearEditingZohoTransferId
          ? null
          : (editingZohoTransferId ?? this.editingZohoTransferId),
      editingTransferNumber: clearEditingTransferNumber
          ? null
          : (editingTransferNumber ?? this.editingTransferNumber),
      editingTransferDate: clearEditingTransferDate
          ? null
          : (editingTransferDate ?? this.editingTransferDate),
      status: status ?? this.status,
    );
  }

  @override
  List<Object?> get props => [
    direction,
    rows,
    defaultWarehouse,
    currentLocation,
    isLoading,
    isLiveData,
    errorMessage,
    successMessage,
    editingTransferId,
    editingZohoTransferId,
    editingTransferNumber,
    editingTransferDate,
    status,
  ];
}

// --- Bloc ---

/// Business Logic Component driving both the Issue-to-Van and Stock-Unloading
/// planning grids and their submission as Zoho Transfer Orders.
class StockTransferBloc extends Bloc<StockTransferEvent, StockTransferState> {
  final StockTransferRepository _stockTransferRepository;

  StockTransferBloc({
    required StockTransferRepository stockTransferRepository,
  }) : _stockTransferRepository = stockTransferRepository,
       super(const StockTransferState()) {
    on<LoadIssueGrid>(_onLoadIssueGrid);
    on<LoadIssueGridWithDemand>(_onLoadIssueGridWithDemand);
    on<LoadUnloadGrid>(_onLoadUnloadGrid);
    on<LoadIssueGridForEdit>(_onLoadIssueGridForEdit);
    on<LoadUnloadGridForEdit>(_onLoadUnloadGridForEdit);
    on<UpdateExtraQty>(_onUpdateExtraQty);
    on<UpdateRowUnit>(_onUpdateRowUnit);
    on<AddExtraItem>(_onAddExtraItem);
    on<RemoveRow>(_onRemoveRow);
    on<SubmitTransfer>(_onSubmitTransfer);
    on<ClearMessages>(_onClearMessages);
  }

  Future<void> _onLoadIssueGrid(
    LoadIssueGrid event,
    Emitter<StockTransferState> emit,
  ) async {
    final invoiceQtyByItem =
        _stockTransferRepository.getTodaysInvoicedQuantities();
    await _loadIssueGridWithQtyMap(emit, invoiceQtyByItem);
  }

  Future<void> _onLoadIssueGridWithDemand(
    LoadIssueGridWithDemand event,
    Emitter<StockTransferState> emit,
  ) async {
    // Order demand fills Col 2 (invoiceQty) so transfer qty = demand + extra.
    final demand = Map<String, double>.from(event.demandByItemId)
      ..removeWhere((_, qty) => qty <= 0);
    await _loadIssueGridWithQtyMap(emit, demand);
  }

  /// Shared Issue-to-Van grid builder: van stock ∪ keys in [qtyByItemId].
  Future<void> _loadIssueGridWithQtyMap(
    Emitter<StockTransferState> emit,
    Map<String, double> qtyByItemId,
  ) async {
    emit(
      state.copyWith(
        isLoading: true,
        direction: StockTransferDirection.load,
        errorMessage: null,
        successMessage: null,
        clearEditingTransferId: true,
        clearEditingZohoTransferId: true,
        clearEditingTransferNumber: true,
        clearEditingTransferDate: true,
        status: 'draft',
      ),
    );
    try {
      final (:items, :live) =
          await _stockTransferRepository.loadCurrentLocationItems();
      final currentItems = items;

      // Union of fetched items and demand/invoiced items — a sold-out item
      // (stock 0) still appears when it has quantity to transfer. Catalog
      // items with neither stock nor demand stay off the grid.
      final itemsById = <String, Item>{for (final it in currentItems) it.id: it};
      final cachedItems = _stockTransferRepository.getItems();
      for (final itemId in qtyByItemId.keys) {
        itemsById.putIfAbsent(itemId, () {
          return cachedItems.firstWhere(
            (it) => it.id == itemId,
            orElse: () => Item(
              id: itemId,
              name: 'Unknown Item',
              sku: '',
              rate: 0,
              stock: 0,
              description: '',
              taxName: '',
              taxPercentage: 0,
            ),
          );
        });
      }

      final rows = buildIssueToVanRows(itemsById.values, qtyByItemId);

      final (:defaultWarehouse, :currentLocation) =
          _stockTransferRepository.resolveTransferLocations();

      emit(
        state.copyWith(
          rows: rows,
          defaultWarehouse: defaultWarehouse,
          currentLocation: currentLocation,
          isLoading: false,
          isLiveData: live,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: userFacingMessage(e)));
    }
  }

  Future<void> _onLoadUnloadGrid(
    LoadUnloadGrid event,
    Emitter<StockTransferState> emit,
  ) async {
    emit(
      state.copyWith(
        isLoading: true,
        direction: StockTransferDirection.unload,
        errorMessage: null,
        successMessage: null,
        clearEditingTransferId: true,
        clearEditingZohoTransferId: true,
        clearEditingTransferNumber: true,
        clearEditingTransferDate: true,
        status: 'draft',
      ),
    );
    try {
      final vanItems = _stockTransferRepository
          .getItems()
          .where((it) => it.stock > 0)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      final rows = vanItems
          .map(
            (item) => StockTransferRow(
              item: item,
              currentStock: item.stock,
              extraQty: item.stock, // default: unload the full balance
            ),
          )
          .toList();

      final (:defaultWarehouse, :currentLocation) =
          _stockTransferRepository.resolveTransferLocations();

      emit(
        state.copyWith(
          rows: rows,
          defaultWarehouse: defaultWarehouse,
          currentLocation: currentLocation,
          isLoading: false,
          isLiveData: true,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: userFacingMessage(e)));
    }
  }

  /// Shared line-quantity index built from an existing transfer's own lines,
  /// used to prefill the grid rows opened via [LoadIssueGridForEdit] /
  /// [LoadUnloadGridForEdit].
  ({
    Map<String, double> qty,
    Map<String, String> uom,
    Map<String, double> conversionRate,
  }) _lineIndex(StockTransfer transfer) {
    final qty = <String, double>{};
    final uom = <String, String>{};
    final conversionRate = <String, double>{};
    for (final line in transfer.lines) {
      qty[line.item.id] = line.quantity;
      uom[line.item.id] = line.uom;
      conversionRate[line.item.id] = line.conversionRate;
    }
    return (qty: qty, uom: uom, conversionRate: conversionRate);
  }

  Future<void> _onLoadIssueGridForEdit(
    LoadIssueGridForEdit event,
    Emitter<StockTransferState> emit,
  ) async {
    final transfer = event.transfer;
    emit(
      state.copyWith(
        isLoading: true,
        direction: StockTransferDirection.load,
        errorMessage: null,
        successMessage: null,
      ),
    );
    try {
      final (:items, :live) =
          await _stockTransferRepository.loadCurrentLocationItems();

      final itemsById = <String, Item>{for (final it in items) it.id: it};
      for (final line in transfer.lines) {
        itemsById.putIfAbsent(line.item.id, () => line.item);
      }

      final index = _lineIndex(transfer);
      final rows =
          [
              for (final item in itemsById.values)
                if (item.stock > 0 || index.qty.containsKey(item.id))
                  StockTransferRow(
                    item: item,
                    currentStock: item.stock,
                    extraQty: index.qty[item.id] ?? 0,
                    uom: index.uom[item.id] ?? '',
                    conversionRate: index.conversionRate[item.id] ?? 1.0,
                  ),
            ]
            ..sort((a, b) => a.item.name.compareTo(b.item.name));

      final (:defaultWarehouse, :currentLocation) =
          _stockTransferRepository.resolveTransferLocations();

      emit(
        state.copyWith(
          rows: rows,
          defaultWarehouse: defaultWarehouse,
          currentLocation: currentLocation,
          isLoading: false,
          isLiveData: live,
          editingTransferId: transfer.id,
          editingZohoTransferId: transfer.zohoTransferId,
          editingTransferNumber: transfer.transferNumber,
          editingTransferDate: transfer.date,
          status: transfer.status,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: userFacingMessage(e)));
    }
  }

  Future<void> _onLoadUnloadGridForEdit(
    LoadUnloadGridForEdit event,
    Emitter<StockTransferState> emit,
  ) async {
    final transfer = event.transfer;
    emit(
      state.copyWith(
        isLoading: true,
        direction: StockTransferDirection.unload,
        errorMessage: null,
        successMessage: null,
      ),
    );
    try {
      final vanItemsById = <String, Item>{
        for (final it in _stockTransferRepository.getItems())
          if (it.stock > 0) it.id: it,
      };
      for (final line in transfer.lines) {
        vanItemsById.putIfAbsent(line.item.id, () => line.item);
      }

      final index = _lineIndex(transfer);
      final rows =
          vanItemsById.values
              .map(
                (item) => StockTransferRow(
                  item: item,
                  currentStock: item.stock,
                  extraQty: index.qty[item.id] ?? 0,
                  uom: index.uom[item.id] ?? '',
                  conversionRate: index.conversionRate[item.id] ?? 1.0,
                ),
              )
              .toList()
            ..sort((a, b) => a.item.name.compareTo(b.item.name));

      final (:defaultWarehouse, :currentLocation) =
          _stockTransferRepository.resolveTransferLocations();

      emit(
        state.copyWith(
          rows: rows,
          defaultWarehouse: defaultWarehouse,
          currentLocation: currentLocation,
          isLoading: false,
          isLiveData: true,
          editingTransferId: transfer.id,
          editingZohoTransferId: transfer.zohoTransferId,
          editingTransferNumber: transfer.transferNumber,
          editingTransferDate: transfer.date,
          status: transfer.status,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: userFacingMessage(e)));
    }
  }

  void _onUpdateExtraQty(
    UpdateExtraQty event,
    Emitter<StockTransferState> emit,
  ) {
    final rows = List<StockTransferRow>.from(state.rows);
    final idx = rows.indexWhere((r) => r.item.id == event.itemId);
    if (idx < 0) return;

    // Entered in the row's selected unit — convert to base for storage.
    var qty = event.quantity * rows[idx].conversionRate;
    if (qty < 0) qty = 0;
    if (state.direction == StockTransferDirection.unload) {
      // Unload can never move more than the van's current balance.
      qty = qty > rows[idx].currentStock ? rows[idx].currentStock : qty;
    }

    rows[idx] = rows[idx].copyWith(extraQty: qty);
    emit(state.copyWith(rows: rows, errorMessage: null));
  }

  void _onUpdateRowUnit(UpdateRowUnit event, Emitter<StockTransferState> emit) {
    final rows = List<StockTransferRow>.from(state.rows);
    final idx = rows.indexWhere((r) => r.item.id == event.itemId);
    if (idx < 0) return;
    rows[idx] = rows[idx].copyWith(
      uom: event.uom,
      conversionRate: event.conversionRate <= 0 ? 1.0 : event.conversionRate,
    );
    emit(state.copyWith(rows: rows, errorMessage: null));
  }

  void _onAddExtraItem(AddExtraItem event, Emitter<StockTransferState> emit) {
    if (state.direction == StockTransferDirection.unload) {
      // Stock Unloading only operates on items already on the van.
      return;
    }
    final baseQty = event.quantity * event.conversionRate;
    final rows = List<StockTransferRow>.from(state.rows);
    final idx = rows.indexWhere((r) => r.item.id == event.item.id);
    if (idx >= 0) {
      rows[idx] = rows[idx].copyWith(
        extraQty: rows[idx].extraQty + baseQty,
        uom: event.uom,
        conversionRate: event.conversionRate <= 0 ? 1.0 : event.conversionRate,
      );
    } else {
      rows.add(
        StockTransferRow(
          item: event.item,
          currentStock: event.item.stock,
          extraQty: baseQty,
          uom: event.uom,
          conversionRate:
              event.conversionRate <= 0 ? 1.0 : event.conversionRate,
        ),
      );
      rows.sort((a, b) => a.item.name.compareTo(b.item.name));
    }
    emit(state.copyWith(rows: rows, errorMessage: null));
  }

  void _onRemoveRow(RemoveRow event, Emitter<StockTransferState> emit) {
    final rows = List<StockTransferRow>.from(state.rows);
    rows.removeWhere((r) => r.item.id == event.itemId);
    emit(state.copyWith(rows: rows));
  }

  Future<void> _onSubmitTransfer(
    SubmitTransfer event,
    Emitter<StockTransferState> emit,
  ) async {
    if (state.isReadOnly) {
      emit(
        state.copyWith(
          errorMessage:
              'This transfer has already been processed in Zoho and can no '
              'longer be edited.',
        ),
      );
      return;
    }

    final linesToTransfer = state.rows
        .where((r) => state.transferQtyFor(r) > 0)
        .toList();
    if (linesToTransfer.isEmpty) {
      emit(
        state.copyWith(
          errorMessage: 'Please enter a quantity for at least one item',
        ),
      );
      return;
    }

    final (:defaultWarehouse, :currentLocation) =
        _stockTransferRepository.resolveTransferLocations();
    if (defaultWarehouse.id.isEmpty) {
      emit(
        state.copyWith(
          errorMessage:
              'Primary location is not configured in Zoho for this organization. '
              'Contact your administrator before issuing stock to the van.',
        ),
      );
      return;
    }
    if (currentLocation.id.isEmpty) {
      emit(
        state.copyWith(
          errorMessage:
              'Unable to resolve your van location. Please sync masters and re-select your route.',
        ),
      );
      return;
    }

    emit(state.copyWith(isLoading: true));
    try {
      final isLoad = state.direction == StockTransferDirection.load;
      final fromLocationId = isLoad ? defaultWarehouse.id : currentLocation.id;
      final toLocationId = isLoad ? currentLocation.id : defaultWarehouse.id;

      final isUpdate = state.isEditingExisting;
      final id = isUpdate
          ? state.editingTransferId!
          : 'temp_to_${DateTime.now().millisecondsSinceEpoch}';
      final transfer = StockTransfer(
        id: id,
        transferNumber: isUpdate
            ? (state.editingTransferNumber ?? '')
            : 'TO-TEMP-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
        date: isUpdate ? (state.editingTransferDate ?? DateTime.now()) : DateTime.now(),
        direction: state.direction,
        fromLocationId: fromLocationId,
        toLocationId: toLocationId,
        lines: linesToTransfer
            .map(
              (r) => StockTransferLine(
                item: r.item,
                // Base units — the payload and local stock math stay
                // base-unit; uom/conversionRate ride along for display.
                quantity: state.transferQtyFor(r),
                uom: r.displayUom,
                conversionRate: r.conversionRate,
              ),
            )
            .toList(),
        notes: event.notes,
        isPendingSync: true,
        zohoTransferId: state.editingZohoTransferId,
      );

      final result = await _stockTransferRepository.submitStockTransfer(
        transfer,
        isUpdate: isUpdate,
      );

      emit(
        state.copyWith(
          isLoading: false,
          successMessage: result.message(
            isUpdate
                ? 'Transfer updated successfully'
                : isLoad
                ? 'Stock issued to van successfully'
                : 'Stock unloaded successfully',
          ),
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: userFacingMessage(e)));
    }
  }

  void _onClearMessages(ClearMessages event, Emitter<StockTransferState> emit) {
    emit(state.copyWith(errorMessage: null, successMessage: null));
  }
}
