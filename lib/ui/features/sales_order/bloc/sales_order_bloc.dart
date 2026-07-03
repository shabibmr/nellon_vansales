// ignore_for_file: prefer_initializing_formals
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/models/sales_order.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/models/sales_order_model.dart';

// --- Events ---

/// Base class for all order-related events processed by [SalesOrderBloc].
abstract class SalesOrderEvent extends Equatable {
  const SalesOrderEvent();
  @override
  List<Object?> get props => [];
}

/// Fired to load local sales orders.
class LoadOrders extends SalesOrderEvent {}

/// Fired to download sales orders from Zoho and merge them into the local cache.
class RefreshOrdersFromZoho extends SalesOrderEvent {}

/// Fired to set the active date filter for listing.
class SetDateFilter extends SalesOrderEvent {
  final DateTime? startDate;
  final DateTime? endDate;
  const SetDateFilter({this.startDate, this.endDate});

  @override
  List<Object?> get props => [startDate, endDate];
}

/// Fired to start editing a new blank order.
class StartNewOrder extends SalesOrderEvent {}

/// Fired to start editing an existing order.
class StartEditOrder extends SalesOrderEvent {
  final SalesOrder order;
  const StartEditOrder(this.order);

  @override
  List<Object?> get props => [order];
}

/// Fired to update the active order date under editor.
class UpdateOrderDate extends SalesOrderEvent {
  final DateTime date;
  const UpdateOrderDate(this.date);

  @override
  List<Object?> get props => [date];
}

/// Fired to update the customer details under editor.
class UpdateOrderCustomer extends SalesOrderEvent {
  final Customer customer;
  const UpdateOrderCustomer(this.customer);

  @override
  List<Object?> get props => [customer];
}

/// Fired to update or add line item under active editor.
class AddOrUpdateLineItem extends SalesOrderEvent {
  final Item item;
  final int quantity;
  final double? rate;
  final double? discount;
  const AddOrUpdateLineItem({
    required this.item,
    required this.quantity,
    this.rate,
    this.discount,
  });

  @override
  List<Object?> get props => [item, quantity, rate, discount];
}

/// Fired to drop a specific line item.
class RemoveLineItem extends SalesOrderEvent {
  final Item item;
  const RemoveLineItem(this.item);

  @override
  List<Object?> get props => [item];
}

/// Fired to save the current edited order locally.
class SaveOrder extends SalesOrderEvent {
  final String notes;
  const SaveOrder({required this.notes});

  @override
  List<Object?> get props => [notes];
}

/// Fired to clear successful/failure notifications from the state.
class ClearMessages extends SalesOrderEvent {}

// --- Unified State ---

/// Core state class carrying sales order list, filter criteria, loading flags, and form editor details.
class SalesOrderState extends Equatable {
  final List<SalesOrder> orders;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  // Active Editor Form Fields
  final String? editingOrderId;
  final DateTime? editingDate;
  final Customer? editingCustomer;
  final List<OrderLineItem> editingItems;
  final String editingNotes;
  final bool isEditingNew;

  const SalesOrderState({
    this.orders = const [],
    this.startDate,
    this.endDate,
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
    this.editingOrderId,
    this.editingDate,
    this.editingCustomer,
    this.editingItems = const [],
    this.editingNotes = '',
    this.isEditingNew = false,
  });

  /// Evaluates and returns the loaded orders filtered by the active date range.
  List<SalesOrder> get filteredOrders {
    return orders.where((ord) {
      final ordDay = DateTime(ord.date.year, ord.date.month, ord.date.day);
      if (startDate != null) {
        final startDay = DateTime(startDate!.year, startDate!.month, startDate!.day);
        if (ordDay.isBefore(startDay)) return false;
      }
      if (endDate != null) {
        final endDay = DateTime(endDate!.year, endDate!.month, endDate!.day);
        if (ordDay.isAfter(endDay)) return false;
      }
      return true;
    }).toList();
  }

  SalesOrderState copyWith({
    List<SalesOrder>? orders,
    DateTime? startDate,
    DateTime? endDate,
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    String? editingOrderId,
    DateTime? editingDate,
    Customer? editingCustomer,
    List<OrderLineItem>? editingItems,
    String? editingNotes,
    bool? isEditingNew,
  }) {
    return SalesOrderState(
      orders: orders ?? this.orders,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      successMessage: successMessage ?? this.successMessage,
      editingOrderId: editingOrderId ?? this.editingOrderId,
      editingDate: editingDate ?? this.editingDate,
      editingCustomer: editingCustomer ?? this.editingCustomer,
      editingItems: editingItems ?? this.editingItems,
      editingNotes: editingNotes ?? this.editingNotes,
      isEditingNew: isEditingNew ?? this.isEditingNew,
    );
  }

  @override
  List<Object?> get props => [
        orders,
        startDate,
        endDate,
        isLoading,
        errorMessage,
        successMessage,
        editingOrderId,
        editingDate,
        editingCustomer,
        editingItems,
        editingNotes,
        isEditingNew,
      ];
}

// --- Bloc ---

/// Business Logic Component managing order listing, filtering, creation, and synchronization.
class SalesOrderBloc extends Bloc<SalesOrderEvent, SalesOrderState> {
  final SalesRepository _salesRepository;
  final SyncRepository _syncRepository;

  SalesOrderBloc({
    required SalesRepository salesRepository,
    required SyncRepository syncRepository,
  })  : _salesRepository = salesRepository,
        _syncRepository = syncRepository,
        super(const SalesOrderState()) {
    on<LoadOrders>(_onLoadOrders);
    on<RefreshOrdersFromZoho>(_onRefreshOrdersFromZoho);
    on<SetDateFilter>(_onSetDateFilter);
    on<StartNewOrder>(_onStartNewOrder);
    on<StartEditOrder>(_onStartEditOrder);
    on<UpdateOrderDate>(_onUpdateOrderDate);
    on<UpdateOrderCustomer>(_onUpdateOrderCustomer);
    on<AddOrUpdateLineItem>(_onAddOrUpdateLineItem);
    on<RemoveLineItem>(_onRemoveLineItem);
    on<SaveOrder>(_onSaveOrder);
    on<ClearMessages>(_onClearMessages);
  }

  Future<void> _onLoadOrders(LoadOrders event, Emitter<SalesOrderState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final loaded = _salesRepository.getLocalOrders();
      emit(state.copyWith(
        orders: loaded,
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onRefreshOrdersFromZoho(
      RefreshOrdersFromZoho event, Emitter<SalesOrderState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final loaded = await _salesRepository.fetchRemoteOrders();
      emit(state.copyWith(orders: loaded, isLoading: false));
    } catch (e) {
      // Offline-first: surface the error but keep the cached list intact.
      emit(state.copyWith(
        orders: _salesRepository.getLocalOrders(),
        isLoading: false,
        errorMessage: e.toString(),
      ));
    }
  }

  void _onSetDateFilter(SetDateFilter event, Emitter<SalesOrderState> emit) {
    emit(state.copyWith(
      startDate: event.startDate,
      endDate: event.endDate,
    ));
  }

  void _onStartNewOrder(StartNewOrder event, Emitter<SalesOrderState> emit) {
    emit(state.copyWith(
      editingOrderId: 'temp_so_${DateTime.now().millisecondsSinceEpoch}',
      editingDate: DateTime.now(),
      editingCustomer: null,
      editingItems: const [],
      editingNotes: '',
      isEditingNew: true,
      errorMessage: null,
      successMessage: null,
    ));
  }

  void _onStartEditOrder(StartEditOrder event, Emitter<SalesOrderState> emit) {
    final customers = _salesRepository.getCustomers();
    final customer = customers.firstWhere(
      (c) => c.id == event.order.customerId,
      orElse: () => Customer(
        id: event.order.customerId,
        name: event.order.customerName,
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

    emit(state.copyWith(
      editingOrderId: event.order.id,
      editingDate: event.order.date,
      editingCustomer: customer,
      editingItems: List.from(event.order.items),
      editingNotes: event.order.notes,
      isEditingNew: false,
      errorMessage: null,
      successMessage: null,
    ));
  }

  void _onUpdateOrderDate(UpdateOrderDate event, Emitter<SalesOrderState> emit) {
    emit(state.copyWith(editingDate: event.date));
  }

  void _onUpdateOrderCustomer(UpdateOrderCustomer event, Emitter<SalesOrderState> emit) {
    emit(state.copyWith(editingCustomer: event.customer));
  }

  void _onAddOrUpdateLineItem(AddOrUpdateLineItem event, Emitter<SalesOrderState> emit) {
    final items = List<OrderLineItem>.from(state.editingItems);
    final idx = items.indexWhere((line) => line.item.id == event.item.id);

    // Sales Orders are forward-bookings and don't strictly require local van stock validation.
    // However, we still allow adding the line item.
    if (idx >= 0) {
      if (event.quantity <= 0) {
        items.removeAt(idx);
      } else {
        items[idx] = items[idx].copyWith(
          quantity: event.quantity,
          rate: event.rate,
          discount: event.discount,
        );
      }
    } else {
      if (event.quantity > 0) {
        items.add(OrderLineItem(
          item: event.item,
          quantity: event.quantity,
          rate: event.rate ?? event.item.rate,
          taxPercentage: event.item.taxPercentage,
          discount: event.discount ?? 0.0,
        ));
      }
    }
    emit(state.copyWith(editingItems: items, errorMessage: null));
  }

  void _onRemoveLineItem(RemoveLineItem event, Emitter<SalesOrderState> emit) {
    final items = List<OrderLineItem>.from(state.editingItems);
    items.removeWhere((line) => line.item.id == event.item.id);
    emit(state.copyWith(editingItems: items));
  }

  Future<void> _onSaveOrder(SaveOrder event, Emitter<SalesOrderState> emit) async {
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
      final tempId = state.editingOrderId ?? 'temp_so_${DateTime.now().millisecondsSinceEpoch}';

      String orderNum;
      String? existingZohoOrderId;
      if (isNew) {
        orderNum = 'SO-TEMP-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
      } else {
        final originalOrder = state.orders.firstWhere((ord) => ord.id == tempId);
        orderNum = originalOrder.orderNumber;
        existingZohoOrderId = originalOrder.zohoOrderId;
      }

      final order = SalesOrder(
        id: tempId,
        orderNumber: orderNum,
        customerId: state.editingCustomer!.id,
        customerName: state.editingCustomer!.name,
        date: state.editingDate ?? DateTime.now(),
        shipmentDate: (state.editingDate ?? DateTime.now()).add(const Duration(days: 7)),
        items: state.editingItems,
        notes: event.notes,
        isPendingSync: true,
        zohoOrderId: existingZohoOrderId,
      );

      await _salesRepository.saveLocalOrder(order);

      // An order that has already synced (has a permanent zohoOrderId) is updated
      // in place; otherwise it is a create still pending its first sync.
      final isUpdate = existingZohoOrderId != null && existingZohoOrderId.isNotEmpty;
      final payload = SalesOrderModel.fromDomain(order).toJson();
      if (isUpdate) {
        // Update routes to /salesorders/{realId}, so target the permanent Zoho id.
        payload['salesorder_id'] = existingZohoOrderId;
      }

      final syncItem = SyncQueueItem(
        id: tempId,
        type: isUpdate ? 'update_sales_order' : 'sales_order',
        payload: payload,
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      );
      await _salesRepository.enqueueSyncItem(syncItem);

      _syncRepository.triggerSync();

      final updatedOrders = _salesRepository.getLocalOrders();

      emit(state.copyWith(
        orders: updatedOrders,
        isLoading: false,
        successMessage: 'Sales Order saved successfully',
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      ));
    }
  }

  void _onClearMessages(ClearMessages event, Emitter<SalesOrderState> emit) {
    emit(state.copyWith(errorMessage: null, successMessage: null));
  }
}
