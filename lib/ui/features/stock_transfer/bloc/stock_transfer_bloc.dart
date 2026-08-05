// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/stock_transfer.dart';
import '../../../../domain/models/warehouse.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/models/stock_transfer_model.dart';
import '../../../core/utils/date_filter.dart';
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

  const StockTransferState({
    this.direction = StockTransferDirection.load,
    this.rows = const [],
    this.defaultWarehouse = const Warehouse(id: '', name: 'Default Warehouse', address: ''),
    this.currentLocation = const Warehouse(id: '', name: 'Current Location', address: ''),
    this.isLoading = false,
    this.isLiveData = false,
    this.errorMessage,
    this.successMessage,
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

  StockTransferState copyWith({
    StockTransferDirection? direction,
    List<StockTransferRow>? rows,
    Warehouse? defaultWarehouse,
    Warehouse? currentLocation,
    bool? isLoading,
    bool? isLiveData,
    String? errorMessage,
    String? successMessage,
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
  ];
}

// --- Bloc ---

/// Business Logic Component driving both the Issue-to-Van and Stock-Unloading
/// planning grids and their submission as Zoho Transfer Orders.
class StockTransferBloc extends Bloc<StockTransferEvent, StockTransferState> {
  final SalesRepository _salesRepository;
  final SyncRepository _syncRepository;

  StockTransferBloc({
    required SalesRepository salesRepository,
    required SyncRepository syncRepository,
  }) : _salesRepository = salesRepository,
       _syncRepository = syncRepository,
       super(const StockTransferState()) {
    on<LoadIssueGrid>(_onLoadIssueGrid);
    on<LoadIssueGridWithDemand>(_onLoadIssueGridWithDemand);
    on<LoadUnloadGrid>(_onLoadUnloadGrid);
    on<UpdateExtraQty>(_onUpdateExtraQty);
    on<UpdateRowUnit>(_onUpdateRowUnit);
    on<AddExtraItem>(_onAddExtraItem);
    on<RemoveRow>(_onRemoveRow);
    on<SubmitTransfer>(_onSubmitTransfer);
    on<ClearMessages>(_onClearMessages);
  }

  /// Resolves the organization's default (primary) warehouse location, falling
  /// back to the first known warehouse if none is flagged primary.
  Warehouse _resolveDefaultWarehouse() {
    final warehouses = _salesRepository.getWarehouses();
    if (warehouses.isEmpty) {
      return const Warehouse(id: '', name: 'Default Warehouse', address: '');
    }
    final primaryId = _salesRepository.primaryWarehouseId;
    if (primaryId != null && primaryId.isNotEmpty) {
      for (final w in warehouses) {
        if (w.id == primaryId) return w;
      }
    }
    return warehouses.firstWhere(
      (w) => w.isPrimary,
      orElse: () => warehouses.first,
    );
  }

  Warehouse _resolveCurrentLocation() {
    final id = _salesRepository.assignedWarehouseId;
    final warehouses = _salesRepository.getWarehouses();
    return warehouses.firstWhere(
      (w) => w.id == id,
      orElse: () =>
          Warehouse(id: id ?? '', name: 'Current Location', address: ''),
    );
  }

  Future<void> _onLoadIssueGrid(
    LoadIssueGrid event,
    Emitter<StockTransferState> emit,
  ) async {
    // Today's invoiced quantities per item, scoped to the current location
    // (getLocalInvoices() is already session-location scoped).
    final today = DateTime.now();
    final todaysInvoices = filterByDateRange(
      _salesRepository.getLocalInvoices(),
      (inv) => inv.date,
      startDate: today,
      endDate: today,
    );
    final invoiceQtyByItem = <String, double>{};
    for (final inv in todaysInvoices) {
      for (final line in inv.items) {
        // Base-unit quantities — invoice lines may be in alternate units.
        invoiceQtyByItem[line.item.id] =
            (invoiceQtyByItem[line.item.id] ?? 0) + line.quantityInBase;
      }
    }
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
      ),
    );
    try {
      final locationId = _salesRepository.assignedWarehouseId ?? '';
      List<Item> currentItems;
      var live = false;
      try {
        currentItems = await _salesRepository.fetchRemoteItems(
          locationId: locationId,
        );
        live = true;
      } catch (_) {
        currentItems = _salesRepository.getItems();
      }

      // Union of current-stock items and demand/invoiced items — an item may
      // have sold out (stock 0) yet still need to appear for the transfer.
      final itemsById = <String, Item>{for (final it in currentItems) it.id: it};
      final cachedItems = _salesRepository.getItems();
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

      final rows =
          itemsById.values
              .map(
                (item) => StockTransferRow(
                  item: item,
                  currentStock: item.stock,
                  invoiceQty: qtyByItemId[item.id] ?? 0,
                ),
              )
              .toList()
            ..sort((a, b) => a.item.name.compareTo(b.item.name));

      final defaultWarehouse = _resolveDefaultWarehouse();
      final currentLocation = _resolveCurrentLocation();

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
      ),
    );
    try {
      final vanItems = _salesRepository
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

      final defaultWarehouse = _resolveDefaultWarehouse();
      final currentLocation = _resolveCurrentLocation();

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

    final defaultWarehouse = _resolveDefaultWarehouse();
    final currentLocationId = _salesRepository.assignedWarehouseId;
    if (defaultWarehouse == null || currentLocationId == null) {
      emit(
        state.copyWith(
          errorMessage:
              'Unable to resolve warehouse/location. Please sync masters and re-select your route.',
        ),
      );
      return;
    }

    emit(state.copyWith(isLoading: true));
    try {
      final isLoad = state.direction == StockTransferDirection.load;
      final fromLocationId = isLoad ? defaultWarehouse.id : currentLocationId;
      final toLocationId = isLoad ? currentLocationId : defaultWarehouse.id;

      final tempId = 'temp_to_${DateTime.now().millisecondsSinceEpoch}';
      final transfer = StockTransfer(
        id: tempId,
        transferNumber:
            'TO-TEMP-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
        date: DateTime.now(),
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
      );

      await _salesRepository.saveLocalStockTransfer(transfer);

      final syncItem = SyncQueueItem(
        id: tempId,
        type: 'stock_transfer',
        payload: StockTransferModel.fromDomain(transfer).toJson(),
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      );
      await _salesRepository.enqueueSyncItem(syncItem);

      unawaited(_syncRepository.triggerSync());

      emit(
        state.copyWith(
          isLoading: false,
          successMessage: isLoad
              ? 'Stock issued to van successfully'
              : 'Stock unloaded successfully',
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
