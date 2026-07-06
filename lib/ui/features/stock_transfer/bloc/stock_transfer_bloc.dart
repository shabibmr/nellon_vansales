// ignore_for_file: prefer_initializing_formals
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/stock_transfer.dart';
import '../../../../domain/models/warehouse.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/models/item_model.dart';
import '../../../../data/models/stock_transfer_model.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../core/utils/date_filter.dart';

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
class StockTransferRow extends Equatable {
  final Item item;
  final int currentStock;
  final int invoiceQty;
  final int extraQty;

  const StockTransferRow({
    required this.item,
    required this.currentStock,
    this.invoiceQty = 0,
    this.extraQty = 0,
  });

  /// Col 3 — current stock plus today's invoiced quantity.
  int get subtotal => currentStock + invoiceQty;

  /// Col 5 — resulting van stock after the transfer completes.
  int get grandTotal => subtotal + extraQty;

  StockTransferRow copyWith({
    Item? item,
    int? currentStock,
    int? invoiceQty,
    int? extraQty,
  }) {
    return StockTransferRow(
      item: item ?? this.item,
      currentStock: currentStock ?? this.currentStock,
      invoiceQty: invoiceQty ?? this.invoiceQty,
      extraQty: extraQty ?? this.extraQty,
    );
  }

  @override
  List<Object?> get props => [item, currentStock, invoiceQty, extraQty];
}

// --- Events ---

abstract class StockTransferEvent extends Equatable {
  const StockTransferEvent();
  @override
  List<Object?> get props => [];
}

/// Loads the Issue-to-Van planning grid (warehouse → current location).
class LoadIssueGrid extends StockTransferEvent {}

/// Loads the Stock-Unloading grid (current location → warehouse).
class LoadUnloadGrid extends StockTransferEvent {}

/// Updates the editable quantity (Col 4 for load; transfer qty for unload) for an existing row.
class UpdateExtraQty extends StockTransferEvent {
  final String itemId;
  final int quantity;
  const UpdateExtraQty({required this.itemId, required this.quantity});

  @override
  List<Object?> get props => [itemId, quantity];
}

/// Adds a new item to the grid (not present in Col 1/Col 2) with an initial extra quantity.
class AddExtraItem extends StockTransferEvent {
  final Item item;
  final int quantity;
  const AddExtraItem({required this.item, required this.quantity});

  @override
  List<Object?> get props => [item, quantity];
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
  final bool isLoading;
  final bool isLiveData;
  final String? errorMessage;
  final String? successMessage;

  const StockTransferState({
    this.direction = StockTransferDirection.load,
    this.rows = const [],
    this.isLoading = false,
    this.isLiveData = false,
    this.errorMessage,
    this.successMessage,
  });

  /// Quantity that actually transfers for [row], depending on [direction].
  int transferQtyFor(StockTransferRow row) {
    return direction == StockTransferDirection.load
        ? row.invoiceQty + row.extraQty
        : row.extraQty;
  }

  /// Sum of [transferQtyFor] across all rows.
  int get totalTransferQty =>
      rows.fold(0, (sum, row) => sum + transferQtyFor(row));

  StockTransferState copyWith({
    StockTransferDirection? direction,
    List<StockTransferRow>? rows,
    bool? isLoading,
    bool? isLiveData,
    String? errorMessage,
    String? successMessage,
  }) {
    return StockTransferState(
      direction: direction ?? this.direction,
      rows: rows ?? this.rows,
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
  final HiveDatabaseService _dbService;
  final ZohoApiClient _apiClient;

  StockTransferBloc({
    required SalesRepository salesRepository,
    required SyncRepository syncRepository,
    required HiveDatabaseService dbService,
    required ZohoApiClient apiClient,
  }) : _salesRepository = salesRepository,
       _syncRepository = syncRepository,
       _dbService = dbService,
       _apiClient = apiClient,
       super(const StockTransferState()) {
    on<LoadIssueGrid>(_onLoadIssueGrid);
    on<LoadUnloadGrid>(_onLoadUnloadGrid);
    on<UpdateExtraQty>(_onUpdateExtraQty);
    on<AddExtraItem>(_onAddExtraItem);
    on<RemoveRow>(_onRemoveRow);
    on<SubmitTransfer>(_onSubmitTransfer);
    on<ClearMessages>(_onClearMessages);
  }

  /// Resolves the organization's default (primary) warehouse location, falling
  /// back to the first known warehouse if none is flagged primary.
  Warehouse? _resolveDefaultWarehouse() {
    final warehouses = _dbService.getWarehouses();
    if (warehouses.isEmpty) return null;
    return warehouses.firstWhere(
      (w) => w.isPrimary,
      orElse: () => warehouses.first,
    );
  }

  Future<void> _onLoadIssueGrid(
    LoadIssueGrid event,
    Emitter<StockTransferState> emit,
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
      final locationId = _dbService.assignedWarehouseId ?? '';
      List<Item> currentItems;
      var live = false;
      try {
        final raw = await _apiClient.fetchItems(locationId);
        currentItems = raw.map<Item>((j) => ItemModel.fromJson(j)).toList();
        live = true;
      } catch (_) {
        currentItems = _salesRepository.getItems();
      }

      // Today's invoiced quantities per item, scoped to the current location
      // (getLocalInvoices() is already session-location scoped).
      final today = DateTime.now();
      final todaysInvoices = filterByDateRange(
        _salesRepository.getLocalInvoices(),
        (inv) => inv.date,
        startDate: today,
        endDate: today,
      );
      final invoiceQtyByItem = <String, int>{};
      for (final inv in todaysInvoices) {
        for (final line in inv.items) {
          invoiceQtyByItem[line.item.id] =
              (invoiceQtyByItem[line.item.id] ?? 0) + line.quantity;
        }
      }

      // Union of current-stock items and invoiced items — an item may have
      // sold out (stock 0, not present in a filtered live response) yet still
      // need to appear because it was invoiced today.
      final itemsById = <String, Item>{for (final it in currentItems) it.id: it};
      final cachedItems = _salesRepository.getItems();
      for (final itemId in invoiceQtyByItem.keys) {
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
                  invoiceQty: invoiceQtyByItem[item.id] ?? 0,
                ),
              )
              .toList()
            ..sort((a, b) => a.item.name.compareTo(b.item.name));

      emit(state.copyWith(rows: rows, isLoading: false, isLiveData: live));
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
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

      emit(
        state.copyWith(rows: rows, isLoading: false, isLiveData: true),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  void _onUpdateExtraQty(
    UpdateExtraQty event,
    Emitter<StockTransferState> emit,
  ) {
    final rows = List<StockTransferRow>.from(state.rows);
    final idx = rows.indexWhere((r) => r.item.id == event.itemId);
    if (idx < 0) return;

    var qty = event.quantity;
    if (qty < 0) qty = 0;
    if (state.direction == StockTransferDirection.unload) {
      // Unload can never move more than the van's current balance.
      qty = qty > rows[idx].currentStock ? rows[idx].currentStock : qty;
    }

    rows[idx] = rows[idx].copyWith(extraQty: qty);
    emit(state.copyWith(rows: rows, errorMessage: null));
  }

  void _onAddExtraItem(AddExtraItem event, Emitter<StockTransferState> emit) {
    if (state.direction == StockTransferDirection.unload) {
      // Stock Unloading only operates on items already on the van.
      return;
    }
    final rows = List<StockTransferRow>.from(state.rows);
    final idx = rows.indexWhere((r) => r.item.id == event.item.id);
    if (idx >= 0) {
      rows[idx] = rows[idx].copyWith(
        extraQty: rows[idx].extraQty + event.quantity,
      );
    } else {
      rows.add(
        StockTransferRow(
          item: event.item,
          currentStock: event.item.stock,
          extraQty: event.quantity,
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
    final currentLocationId = _dbService.assignedWarehouseId;
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
                quantity: state.transferQtyFor(r),
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

      _syncRepository.triggerSync();

      emit(
        state.copyWith(
          isLoading: false,
          successMessage: isLoad
              ? 'Stock issued to van successfully'
              : 'Stock unloaded successfully',
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  void _onClearMessages(ClearMessages event, Emitter<StockTransferState> emit) {
    emit(state.copyWith(errorMessage: null, successMessage: null));
  }
}
