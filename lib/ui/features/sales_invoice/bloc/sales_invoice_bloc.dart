// ignore_for_file: prefer_initializing_formals
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/models/sales_order.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/utils/stock_rules.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/models/sales_invoice_model.dart';
import '../../../../data/services/document_number_service.dart';
import '../../../../data/services/injection.dart';
import '../../../core/utils/date_filter.dart';

// --- Events ---

/// Base class for all billing-related events processed by [SalesInvoiceBloc].
abstract class SalesInvoiceEvent extends Equatable {
  const SalesInvoiceEvent();
  @override
  List<Object?> get props => [];
}

/// Fired to load sales invoices (live-first; falls back to local cache).
class LoadInvoices extends SalesInvoiceEvent {}

/// Fired to download invoices from Zoho and merge them into the local cache.
class RefreshInvoicesFromZoho extends SalesInvoiceEvent {}

/// Fired to set the active date filter for listing.
class SetDateFilter extends SalesInvoiceEvent {
  final DateTime? startDate;
  final DateTime? endDate;
  const SetDateFilter({this.startDate, this.endDate});

  @override
  List<Object?> get props => [startDate, endDate];
}

/// Fired to start editing a new blank invoice.
class StartNewInvoice extends SalesInvoiceEvent {}

/// Fired to start editing an existing invoice.
class StartEditInvoice extends SalesInvoiceEvent {
  final SalesInvoice invoice;
  const StartEditInvoice(this.invoice);

  @override
  List<Object?> get props => [invoice];
}

/// Fired to open a new invoice pre-filled from a sales order being converted.
class StartInvoiceFromOrder extends SalesInvoiceEvent {
  final SalesOrder order;
  const StartInvoiceFromOrder(this.order);

  @override
  List<Object?> get props => [order];
}

/// Fired to update the active invoice date under editor.
class UpdateInvoiceDate extends SalesInvoiceEvent {
  final DateTime date;
  const UpdateInvoiceDate(this.date);

  @override
  List<Object?> get props => [date];
}

/// Fired to update the customer details under editor.
class UpdateInvoiceCustomer extends SalesInvoiceEvent {
  final Customer customer;
  const UpdateInvoiceCustomer(this.customer);

  @override
  List<Object?> get props => [customer];
}

/// Fired to update or add line item under active editor.
class AddOrUpdateLineItem extends SalesInvoiceEvent {
  final Item item;
  final double quantity;
  final double? rate;
  final double? discount;
  final String? uom;
  final String? unitConversionId;
  const AddOrUpdateLineItem({
    required this.item,
    required this.quantity,
    this.rate,
    this.discount,
    this.uom,
    this.unitConversionId,
  });

  @override
  List<Object?> get props =>
      [item, quantity, rate, discount, uom, unitConversionId];
}

/// Fired to drop a specific line item.
class RemoveLineItem extends SalesInvoiceEvent {
  final Item item;
  const RemoveLineItem(this.item);

  @override
  List<Object?> get props => [item];
}

/// Fired to save the current edited invoice locally.
class SaveInvoice extends SalesInvoiceEvent {
  final String notes;
  const SaveInvoice({required this.notes});

  @override
  List<Object?> get props => [notes];
}

/// Batch-converts each open sales order into its own local invoice
/// (one invoice per order) and enqueues Zoho `convert_so` sync items.
class ConvertOrdersBatch extends SalesInvoiceEvent {
  final List<SalesOrder> orders;
  const ConvertOrdersBatch(this.orders);

  @override
  List<Object?> get props => [orders];
}

/// Fired to clear successful/failure notifications from the state.
class ClearMessages extends SalesInvoiceEvent {}

// --- Legacy Checkout Flow Events (Retained for backwards compatibility) ---

/// Fired to append a specific quantity of an inventory [Item] to the active checkout cart.
class AddToCart extends SalesInvoiceEvent {
  final Item item;
  final double quantity;
  const AddToCart(this.item, this.quantity);

  @override
  List<Object?> get props => [item, quantity];
}

/// Fired to completely remove a product from the checkout cart.
class RemoveFromCart extends SalesInvoiceEvent {
  final Item item;
  const RemoveFromCart(this.item);

  @override
  List<Object?> get props => [item];
}

/// Fired to overwrite the checkout quantity of a specific item.
class UpdateCartQuantity extends SalesInvoiceEvent {
  final Item item;
  final double quantity;
  const UpdateCartQuantity(this.item, this.quantity);

  @override
  List<Object?> get props => [item, quantity];
}

/// Fired to discard all contents in the checkout cart.
class ClearCart extends SalesInvoiceEvent {}

/// Fired to create a concrete local invoice and push it to the local cache and sync queue.
class CheckoutRequested extends SalesInvoiceEvent {
  final Customer customer;
  final String notes;
  const CheckoutRequested({required this.customer, required this.notes});

  @override
  List<Object?> get props => [customer, notes];
}

// --- Unified State ---

/// Core state class carrying sales invoice list, filter criteria, loading flags, and form editor details.
class SalesInvoiceState extends Equatable {
  final List<SalesInvoice> invoices;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  // Active Editor Form Fields
  final String? editingInvoiceId;
  final DateTime? editingDate;
  final Customer? editingCustomer;
  final List<InvoiceLineItem> editingItems;
  final String editingNotes;
  final bool isEditingNew;

  /// When the invoice is being created by converting a sales order, this holds
  /// the source order so [SaveInvoice] can mark it invoiced and convert in Zoho.
  final String? sourceOrderId;
  final SalesOrder? sourceOrder;

  const SalesInvoiceState({
    this.invoices = const [],
    this.startDate,
    this.endDate,
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
    this.editingInvoiceId,
    this.editingDate,
    this.editingCustomer,
    this.editingItems = const [],
    this.editingNotes = '',
    this.isEditingNew = false,
    this.sourceOrderId,
    this.sourceOrder,
  });

  /// Computes the legacy cart representation on the fly from editingItems.
  Map<Item, double> get cart => {
    for (final line in editingItems) line.item: line.quantity,
  };

  /// Evaluates and returns the loaded invoices filtered by the active date range.
  List<SalesInvoice> get filteredInvoices => filterByDateRange(
    invoices,
    (inv) => inv.date,
    startDate: startDate,
    endDate: endDate,
  );

  SalesInvoiceState copyWith({
    List<SalesInvoice>? invoices,
    DateTime? Function()? startDate,
    DateTime? Function()? endDate,
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    String? editingInvoiceId,
    DateTime? editingDate,
    Customer? editingCustomer,
    List<InvoiceLineItem>? editingItems,
    String? editingNotes,
    bool? isEditingNew,
    String? sourceOrderId,
    SalesOrder? sourceOrder,
    bool clearSource = false,
    bool clearMessages = false,
  }) {
    return SalesInvoiceState(
      invoices: invoices ?? this.invoices,
      startDate: startDate != null ? startDate() : this.startDate,
      endDate: endDate != null ? endDate() : this.endDate,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearMessages ? null : (errorMessage ?? this.errorMessage),
      successMessage:
          clearMessages ? null : (successMessage ?? this.successMessage),
      editingInvoiceId: editingInvoiceId ?? this.editingInvoiceId,
      editingDate: editingDate ?? this.editingDate,
      editingCustomer: editingCustomer ?? this.editingCustomer,
      editingItems: editingItems ?? this.editingItems,
      editingNotes: editingNotes ?? this.editingNotes,
      isEditingNew: isEditingNew ?? this.isEditingNew,
      sourceOrderId: clearSource ? null : (sourceOrderId ?? this.sourceOrderId),
      sourceOrder: clearSource ? null : (sourceOrder ?? this.sourceOrder),
    );
  }

  @override
  List<Object?> get props => [
    invoices,
    startDate,
    endDate,
    isLoading,
    errorMessage,
    successMessage,
    editingInvoiceId,
    editingDate,
    editingCustomer,
    editingItems,
    editingNotes,
    isEditingNew,
    sourceOrderId,
    sourceOrder,
  ];
}

// --- Bloc ---

/// Business Logic Component managing invoice listing, filtering, creation, and stock updates.
class SalesInvoiceBloc extends Bloc<SalesInvoiceEvent, SalesInvoiceState> {
  final SalesRepository _salesRepository;
  final SyncRepository _syncRepository;

  SalesInvoiceBloc({
    required SalesRepository salesRepository,
    required SyncRepository syncRepository,
  }) : _salesRepository = salesRepository,
       _syncRepository = syncRepository,
       super(SalesInvoiceState(
         startDate: todayDate(),
         endDate: todayDate(),
       )) {
    // List & Editor handlers
    on<LoadInvoices>(_onLoadInvoices);
    on<RefreshInvoicesFromZoho>(_onRefreshInvoicesFromZoho);
    on<SetDateFilter>(_onSetDateFilter);
    on<StartNewInvoice>(_onStartNewInvoice);
    on<StartEditInvoice>(_onStartEditInvoice);
    on<StartInvoiceFromOrder>(_onStartInvoiceFromOrder);
    on<UpdateInvoiceDate>(_onUpdateInvoiceDate);
    on<UpdateInvoiceCustomer>(_onUpdateInvoiceCustomer);
    on<AddOrUpdateLineItem>(_onAddOrUpdateLineItem);
    on<RemoveLineItem>(_onRemoveLineItem);
    on<SaveInvoice>(_onSaveInvoice);
    on<ConvertOrdersBatch>(_onConvertOrdersBatch);
    on<ClearMessages>(_onClearMessages);

    // Legacy cart flow compatibility handlers
    on<AddToCart>(_onAddToCart);
    on<RemoveFromCart>(_onRemoveFromCart);
    on<UpdateCartQuantity>(_onUpdateCartQuantity);
    on<ClearCart>(_onClearCart);
    on<CheckoutRequested>(_onCheckoutRequested);
  }

  /// Live-first load, scoped to the active date filter: fetch from Zoho and
  /// render that; the local cache is only a fallback when the fetch fails.
  Future<void> _loadInvoicesLiveFirst(Emitter<SalesInvoiceState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final loaded = await _salesRepository.fetchRemoteInvoices(
        startDate: state.startDate,
        endDate: state.endDate,
      );
      emit(state.copyWith(invoices: loaded, isLoading: false));
    } catch (e) {
      emit(
        state.copyWith(
          invoices: _salesRepository.getLocalInvoices(),
          isLoading: false,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> _onLoadInvoices(
    LoadInvoices event,
    Emitter<SalesInvoiceState> emit,
  ) =>
      _loadInvoicesLiveFirst(emit);

  Future<void> _onRefreshInvoicesFromZoho(
    RefreshInvoicesFromZoho event,
    Emitter<SalesInvoiceState> emit,
  ) =>
      _loadInvoicesLiveFirst(emit);

  void _onSetDateFilter(SetDateFilter event, Emitter<SalesInvoiceState> emit) {
    emit(state.copyWith(
      startDate: () => event.startDate,
      endDate: () => event.endDate,
    ));
  }

  void _onStartNewInvoice(
    StartNewInvoice event,
    Emitter<SalesInvoiceState> emit,
  ) {
    emit(
      state.copyWith(
        editingInvoiceId: 'temp_inv_${DateTime.now().millisecondsSinceEpoch}',
        editingDate: DateTime.now(),
        editingCustomer: null,
        editingItems: const [],
        editingNotes: '',
        isEditingNew: true,
        errorMessage: null,
        successMessage: null,
        clearSource: true,
      ),
    );
  }

  void _onStartEditInvoice(
    StartEditInvoice event,
    Emitter<SalesInvoiceState> emit,
  ) {
    final customers = _salesRepository.getCustomers();
    final customer = customers.firstWhere(
      (c) => c.id == event.invoice.customerId,
      orElse: () => Customer(
        id: event.invoice.customerId,
        name: event.invoice.customerName,
        companyName: '',
        email: '',
        phone: '',
        address: '',
        outstandingBalance: 0,
        creditLimit: 999999,
        routeId: '',
        sequence: 0,
      ),
    );

    // Ensure remote / ledger-loaded invoices are present for PDF & lookups.
    final invoices = List<SalesInvoice>.from(state.invoices);
    if (!invoices.any((inv) => inv.id == event.invoice.id)) {
      invoices.add(event.invoice);
    }

    emit(
      state.copyWith(
        invoices: invoices,
        editingInvoiceId: event.invoice.id,
        editingDate: event.invoice.date,
        editingCustomer: customer,
        editingItems: List.from(event.invoice.items),
        editingNotes: event.invoice.notes,
        isEditingNew: false,
        errorMessage: null,
        successMessage: null,
        clearSource: true,
      ),
    );
  }

  /// Pre-fills the editor from a sales order being converted to an invoice.
  ///
  /// Line items map 1:1 (identical fields) and are copied directly — this
  /// deliberately bypasses the per-line van-stock cap, since converted invoices
  /// provision stock to the van from the warehouse.
  void _onStartInvoiceFromOrder(
    StartInvoiceFromOrder event,
    Emitter<SalesInvoiceState> emit,
  ) {
    final order = event.order;
    final customers = _salesRepository.getCustomers();
    final customer = customers.firstWhere(
      (c) => c.id == order.customerId,
      orElse: () => Customer(
        id: order.customerId,
        name: order.customerName,
        companyName: '',
        email: '',
        phone: '',
        address: '',
        outstandingBalance: 0,
        creditLimit: 999999,
        routeId: '',
        sequence: 0,
      ),
    );

    final items = order.items
        .map(
          (line) => InvoiceLineItem(
            item: line.item,
            quantity: line.quantity,
            rate: line.rate,
            taxPercentage: line.taxPercentage,
            discount: line.discount,
            uom: line.displayUom,
            unitConversionId: line.unitConversionId,
          ),
        )
        .toList();

    emit(
      state.copyWith(
        editingInvoiceId: 'temp_inv_${DateTime.now().millisecondsSinceEpoch}',
        editingDate: DateTime.now(),
        editingCustomer: customer,
        editingItems: items,
        editingNotes: order.notes,
        isEditingNew: true,
        sourceOrderId: order.id,
        sourceOrder: order,
        errorMessage: null,
        successMessage: null,
      ),
    );
  }

  void _onUpdateInvoiceDate(
    UpdateInvoiceDate event,
    Emitter<SalesInvoiceState> emit,
  ) {
    emit(state.copyWith(editingDate: event.date));
  }

  void _onUpdateInvoiceCustomer(
    UpdateInvoiceCustomer event,
    Emitter<SalesInvoiceState> emit,
  ) {
    emit(state.copyWith(editingCustomer: event.customer));
  }

  void _onAddOrUpdateLineItem(
    AddOrUpdateLineItem event,
    Emitter<SalesInvoiceState> emit,
  ) {
    final items = List<InvoiceLineItem>.from(state.editingItems);
    final idx = items.indexWhere((line) => line.item.id == event.item.id);

    // All stock math runs in base units: convert the entered quantity via
    // the selected unit's conversion rate.
    double originalBaseQty = 0;
    if (!state.isEditingNew && state.editingInvoiceId != null) {
      final originalInvoice = state.invoices.firstWhere(
        (inv) => inv.id == state.editingInvoiceId,
        orElse: () => SalesInvoice(
          id: '',
          invoiceNumber: '',
          customerId: '',
          customerName: '',
          date: DateTime.now(),
          dueDate: DateTime.now(),
          items: const [],
          notes: '',
        ),
      );
      final origLineIndex = originalInvoice.items.indexWhere(
        (line) => line.item.id == event.item.id,
      );
      if (origLineIndex >= 0) {
        originalBaseQty = originalInvoice.items[origLineIndex].quantityInBase;
      }
    }

    final lineUom = (event.uom != null && event.uom!.trim().isNotEmpty)
        ? event.uom!.trim()
        : event.item.uom;
    final requestedBaseQty =
        event.quantity * event.item.conversionRateFor(lineUom);

    final allowedStock = event.item.stock + originalBaseQty;
    try {
      deductStock(
        itemId: event.item.id,
        itemName: event.item.name,
        available: allowedStock,
        requested: requestedBaseQty,
      );
    } on InsufficientStockException catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
      return;
    }

    if (idx >= 0) {
      if (event.quantity <= 0) {
        items.removeAt(idx);
      } else {
        items[idx] = items[idx].copyWith(
          quantity: event.quantity,
          rate: event.rate,
          discount: event.discount,
          uom: lineUom,
          unitConversionId: event.unitConversionId,
        );
      }
    } else {
      if (event.quantity > 0) {
        items.add(
          InvoiceLineItem(
            item: event.item,
            quantity: event.quantity,
            rate: event.rate ?? event.item.rate,
            taxPercentage: event.item.taxPercentage,
            discount: event.discount ?? 0.0,
            uom: lineUom,
            unitConversionId: event.unitConversionId ?? '',
          ),
        );
      }
    }
    emit(state.copyWith(editingItems: items, errorMessage: null));
  }

  void _onRemoveLineItem(
    RemoveLineItem event,
    Emitter<SalesInvoiceState> emit,
  ) {
    final items = List<InvoiceLineItem>.from(state.editingItems);
    items.removeWhere((line) => line.item.id == event.item.id);
    emit(state.copyWith(editingItems: items));
  }

  Future<void> _onSaveInvoice(
    SaveInvoice event,
    Emitter<SalesInvoiceState> emit,
  ) async {
    if (state.editingCustomer == null) {
      emit(state.copyWith(errorMessage: 'Please select a customer'));
      return;
    }
    if (state.editingItems.isEmpty) {
      emit(state.copyWith(errorMessage: 'Please add at least one line item'));
      return;
    }

    emit(state.copyWith(isLoading: true));
    try {
      final isNew = state.isEditingNew;
      final tempId =
          state.editingInvoiceId ??
          'temp_inv_${DateTime.now().millisecondsSinceEpoch}';

      String invoiceNum;
      if (isNew) {
        invoiceNum = await sl<DocumentNumberService>().nextNumber(
          DocType.invoice,
        );
      } else {
        final originalInvoice = state.invoices.firstWhere(
          (inv) => inv.id == tempId,
        );
        invoiceNum = originalInvoice.invoiceNumber;
      }

      final invoice = SalesInvoice(
        id: tempId,
        invoiceNumber: invoiceNum,
        customerId: state.editingCustomer!.id,
        customerName: state.editingCustomer!.name,
        date: state.editingDate ?? DateTime.now(),
        dueDate: (state.editingDate ?? DateTime.now()).add(
          const Duration(days: 7),
        ),
        items: state.editingItems,
        notes: event.notes,
        isPendingSync: true,
      );

      await _salesRepository.saveLocalInvoice(invoice);

      final sourceOrderId = state.sourceOrderId;
      if (sourceOrderId != null) {
        // Conversion path: mark the source order invoiced and enqueue a Zoho
        // convert (not a plain invoice POST) so Zoho creates the invoice from
        // the order and flips its status to "invoiced".
        final orders = _salesRepository.getLocalOrders();
        final order = orders.firstWhere(
          (o) => o.id == sourceOrderId,
          orElse: () => state.sourceOrder!,
        );
        await _salesRepository.saveLocalOrder(
          order.copyWith(
            status: SalesOrderStatus.invoiced,
            convertedInvoiceNumber: invoiceNum,
          ),
        );

        final convertItem = SyncQueueItem(
          id: tempId,
          type: 'convert_so',
          payload: {
            'salesorder_id': order.zohoOrderId ?? order.id,
            'source_order_id': order.id,
            'local_invoice_id': invoice.id,
          },
          status: SyncStatus.pending,
          timestamp: DateTime.now(),
        );
        await _salesRepository.enqueueSyncItem(convertItem);
      } else {
        final syncItem = SyncQueueItem(
          id: tempId,
          type: 'invoice',
          payload: SalesInvoiceModel.fromDomain(invoice).toJson(),
          status: SyncStatus.pending,
          timestamp: DateTime.now(),
        );
        await _salesRepository.enqueueSyncItem(syncItem);
      }

      _syncRepository.triggerSync();

      final updatedInvoices = _salesRepository.getLocalInvoices();

      emit(
        state.copyWith(
          invoices: updatedInvoices,
          isLoading: false,
          successMessage: 'Invoice saved successfully',
          clearSource: true,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  void _onClearMessages(ClearMessages event, Emitter<SalesInvoiceState> emit) {
    emit(state.copyWith(clearMessages: true));
  }

  /// Converts each open order in [event.orders] to a local invoice, continuing
  /// past individual failures (e.g. insufficient stock) and reporting a summary.
  Future<void> _onConvertOrdersBatch(
    ConvertOrdersBatch event,
    Emitter<SalesInvoiceState> emit,
  ) async {
    final candidates = event.orders.where((o) => !o.isConverted).toList();
    if (candidates.isEmpty) {
      emit(
        state.copyWith(
          errorMessage: 'No open orders selected to convert',
        ),
      );
      return;
    }

    emit(state.copyWith(isLoading: true));
    var successCount = 0;
    final failures = <String>[];

    for (var i = 0; i < candidates.length; i++) {
      final order = candidates[i];
      try {
        await _convertSingleOrder(order, batchIndex: i);
        successCount++;
      } on InsufficientStockException catch (e) {
        failures.add('${order.orderNumber}: ${e.toString()}');
      } catch (e) {
        failures.add('${order.orderNumber}: $e');
      }
    }

    _syncRepository.triggerSync();
    final updatedInvoices = _salesRepository.getLocalInvoices();

    if (successCount == 0) {
      emit(
        state.copyWith(
          invoices: updatedInvoices,
          isLoading: false,
          errorMessage: failures.isEmpty
              ? 'No orders converted'
              : 'Convert failed. Load stock first if needed.\n${failures.join('\n')}',
        ),
      );
      return;
    }

    final summary = failures.isEmpty
        ? 'Converted $successCount order${successCount == 1 ? '' : 's'} to invoice'
        : 'Converted $successCount of ${candidates.length}. '
              'Failures (try Items → Create Stock Transfer first):\n'
              '${failures.join('\n')}';

    emit(
      state.copyWith(
        invoices: updatedInvoices,
        isLoading: false,
        successMessage: summary,
      ),
    );
  }

  /// Shared path: create local invoice from [order], mark order invoiced,
  /// enqueue `convert_so` (mirrors the conversion branch of [SaveInvoice]).
  Future<void> _convertSingleOrder(
    SalesOrder order, {
    int batchIndex = 0,
  }) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final tempId = 'temp_inv_${stamp}_$batchIndex';
    final invoiceNum = await sl<DocumentNumberService>().nextNumber(
      DocType.invoice,
    );

    final items = order.items
        .map(
          (line) => InvoiceLineItem(
            item: line.item,
            quantity: line.quantity,
            rate: line.rate,
            taxPercentage: line.taxPercentage,
            discount: line.discount,
            uom: line.displayUom,
            unitConversionId: line.unitConversionId,
          ),
        )
        .toList();

    final invoice = SalesInvoice(
      id: tempId,
      invoiceNumber: invoiceNum,
      customerId: order.customerId,
      customerName: order.customerName,
      date: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(days: 7)),
      items: items,
      notes: order.notes,
      isPendingSync: true,
    );

    await _salesRepository.saveLocalInvoice(invoice);

    final orders = _salesRepository.getLocalOrders();
    final localOrder = orders.firstWhere(
      (o) => o.id == order.id,
      orElse: () => order,
    );
    await _salesRepository.saveLocalOrder(
      localOrder.copyWith(
        status: SalesOrderStatus.invoiced,
        convertedInvoiceNumber: invoiceNum,
      ),
    );

    final convertItem = SyncQueueItem(
      id: tempId,
      type: 'convert_so',
      payload: {
        'salesorder_id': localOrder.zohoOrderId ?? localOrder.id,
        'source_order_id': localOrder.id,
        'local_invoice_id': invoice.id,
      },
      status: SyncStatus.pending,
      timestamp: DateTime.now(),
    );
    await _salesRepository.enqueueSyncItem(convertItem);
  }

  // --- Legacy cart compatibility implementations ---

  void _onAddToCart(AddToCart event, Emitter<SalesInvoiceState> emit) {
    final items = List<InvoiceLineItem>.from(state.editingItems);
    final idx = items.indexWhere((line) => line.item.id == event.item.id);
    final existingQty = idx >= 0 ? items[idx].quantity : 0.0;

    try {
      deductStock(
        itemId: event.item.id,
        itemName: event.item.name,
        available: event.item.stock,
        requested: existingQty + event.quantity,
      );
    } on InsufficientStockException catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
      return;
    }

    if (idx >= 0) {
      items[idx] = items[idx].copyWith(quantity: existingQty + event.quantity);
    } else {
      items.add(
        InvoiceLineItem(
          item: event.item,
          quantity: event.quantity,
          rate: event.item.rate,
          taxPercentage: event.item.taxPercentage,
          uom: event.item.uom,
        ),
      );
    }
    emit(state.copyWith(editingItems: items));
  }

  void _onRemoveFromCart(
    RemoveFromCart event,
    Emitter<SalesInvoiceState> emit,
  ) {
    final items = List<InvoiceLineItem>.from(state.editingItems);
    items.removeWhere((line) => line.item.id == event.item.id);
    emit(state.copyWith(editingItems: items));
  }

  void _onUpdateCartQuantity(
    UpdateCartQuantity event,
    Emitter<SalesInvoiceState> emit,
  ) {
    final items = List<InvoiceLineItem>.from(state.editingItems);
    final idx = items.indexWhere((line) => line.item.id == event.item.id);

    if (event.quantity <= 0) {
      if (idx >= 0) items.removeAt(idx);
    } else {
      try {
        deductStock(
          itemId: event.item.id,
          itemName: event.item.name,
          available: event.item.stock,
          requested: event.quantity,
        );
      } on InsufficientStockException catch (e) {
        emit(state.copyWith(errorMessage: e.toString()));
        return;
      }
      if (idx >= 0) {
        items[idx] = items[idx].copyWith(quantity: event.quantity);
      } else {
        items.add(
          InvoiceLineItem(
            item: event.item,
            quantity: event.quantity,
            rate: event.item.rate,
            taxPercentage: event.item.taxPercentage,
            uom: event.item.uom,
          ),
        );
      }
    }
    emit(state.copyWith(editingItems: items));
  }

  void _onClearCart(ClearCart event, Emitter<SalesInvoiceState> emit) {
    emit(state.copyWith(editingItems: const []));
  }

  Future<void> _onCheckoutRequested(
    CheckoutRequested event,
    Emitter<SalesInvoiceState> emit,
  ) async {
    if (state.isLoading) return;
    if (state.editingItems.isEmpty) {
      emit(state.copyWith(errorMessage: 'Cart is empty'));
      return;
    }

    emit(state.copyWith(isLoading: true, clearMessages: true));
    try {
      final tempId = 'temp_inv_${DateTime.now().millisecondsSinceEpoch}';
      final invoiceNum = await sl<DocumentNumberService>().nextNumber(
        DocType.invoice,
      );
      final invoice = SalesInvoice(
        id: tempId,
        invoiceNumber: invoiceNum,
        customerId: event.customer.id,
        customerName: event.customer.name,
        date: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 7)),
        items: state.editingItems,
        notes: event.notes,
        isPendingSync: true,
      );

      await _salesRepository.saveLocalInvoice(invoice);

      final syncItem = SyncQueueItem(
        id: tempId,
        type: 'invoice',
        payload: SalesInvoiceModel.fromDomain(invoice).toJson(),
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      );
      await _salesRepository.enqueueSyncItem(syncItem);

      _syncRepository.triggerSync();

      final updatedInvoices = _salesRepository.getLocalInvoices();

      emit(
        state.copyWith(
          invoices: updatedInvoices,
          isLoading: false,
          editingItems: const [],
          successMessage: 'Invoice generated & queued offline!',
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }
}
