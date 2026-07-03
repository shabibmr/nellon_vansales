// ignore_for_file: prefer_initializing_formals
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/models/sales_return_model.dart';

// --- Events ---

abstract class SalesReturnEvent extends Equatable {
  const SalesReturnEvent();
  @override
  List<Object?> get props => [];
}

class LoadReturns extends SalesReturnEvent {}

class SetReturnDateFilter extends SalesReturnEvent {
  final DateTime? startDate;
  final DateTime? endDate;
  const SetReturnDateFilter({this.startDate, this.endDate});

  @override
  List<Object?> get props => [startDate, endDate];
}

class StartNewReturn extends SalesReturnEvent {}

class StartEditReturn extends SalesReturnEvent {
  final SalesReturn salesReturn;
  const StartEditReturn(this.salesReturn);

  @override
  List<Object?> get props => [salesReturn];
}

class UpdateReturnDate extends SalesReturnEvent {
  final DateTime date;
  const UpdateReturnDate(this.date);

  @override
  List<Object?> get props => [date];
}

class UpdateReturnCustomer extends SalesReturnEvent {
  final Customer customer;
  const UpdateReturnCustomer(this.customer);

  @override
  List<Object?> get props => [customer];
}

class AddOrUpdateReturnLineItem extends SalesReturnEvent {
  final Item item;
  final int quantity;
  const AddOrUpdateReturnLineItem({required this.item, required this.quantity});

  @override
  List<Object?> get props => [item, quantity];
}

class SetReturnLineItemsForProduct extends SalesReturnEvent {
  final Item item;
  final List<SalesReturnLineItem> lines;
  const SetReturnLineItemsForProduct({required this.item, required this.lines});

  @override
  List<Object?> get props => [item, lines];
}

class RemoveReturnLineItem extends SalesReturnEvent {
  final Item item;
  const RemoveReturnLineItem(this.item);

  @override
  List<Object?> get props => [item];
}

class SaveReturn extends SalesReturnEvent {
  final String reason;
  const SaveReturn({required this.reason});

  @override
  List<Object?> get props => [reason];
}

class ClearReturnMessages extends SalesReturnEvent {}

// --- State ---

class SalesReturnState extends Equatable {
  final List<SalesReturn> returns;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  final String? editingReturnId;
  final DateTime? editingDate;
  final Customer? editingCustomer;
  final List<SalesReturnLineItem> editingItems;
  final String editingReason;
  final bool isEditingNew;

  const SalesReturnState({
    this.returns = const [],
    this.startDate,
    this.endDate,
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
    this.editingReturnId,
    this.editingDate,
    this.editingCustomer,
    this.editingItems = const [],
    this.editingReason = '',
    this.isEditingNew = false,
  });

  List<SalesReturn> get filteredReturns {
    return returns.where((r) {
      final day = DateTime(r.date.year, r.date.month, r.date.day);
      if (startDate != null) {
        final startDay = DateTime(
          startDate!.year,
          startDate!.month,
          startDate!.day,
        );
        if (day.isBefore(startDay)) return false;
      }
      if (endDate != null) {
        final endDay = DateTime(endDate!.year, endDate!.month, endDate!.day);
        if (day.isAfter(endDay)) return false;
      }
      return true;
    }).toList();
  }

  SalesReturnState copyWith({
    List<SalesReturn>? returns,
    DateTime? startDate,
    DateTime? endDate,
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    String? editingReturnId,
    DateTime? editingDate,
    Customer? editingCustomer,
    List<SalesReturnLineItem>? editingItems,
    String? editingReason,
    bool? isEditingNew,
  }) {
    return SalesReturnState(
      returns: returns ?? this.returns,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      successMessage: successMessage ?? this.successMessage,
      editingReturnId: editingReturnId ?? this.editingReturnId,
      editingDate: editingDate ?? this.editingDate,
      editingCustomer: editingCustomer ?? this.editingCustomer,
      editingItems: editingItems ?? this.editingItems,
      editingReason: editingReason ?? this.editingReason,
      isEditingNew: isEditingNew ?? this.isEditingNew,
    );
  }

  @override
  List<Object?> get props => [
    returns,
    startDate,
    endDate,
    isLoading,
    errorMessage,
    successMessage,
    editingReturnId,
    editingDate,
    editingCustomer,
    editingItems,
    editingReason,
    isEditingNew,
  ];
}

// --- Bloc ---

class SalesReturnBloc extends Bloc<SalesReturnEvent, SalesReturnState> {
  final SalesRepository _salesRepository;
  final SyncRepository _syncRepository;

  SalesReturnBloc({
    required SalesRepository salesRepository,
    required SyncRepository syncRepository,
  }) : _salesRepository = salesRepository,
       _syncRepository = syncRepository,
       super(const SalesReturnState()) {
    on<LoadReturns>(_onLoadReturns);
    on<SetReturnDateFilter>(_onSetDateFilter);
    on<StartNewReturn>(_onStartNewReturn);
    on<StartEditReturn>(_onStartEditReturn);
    on<UpdateReturnDate>(_onUpdateReturnDate);
    on<UpdateReturnCustomer>(_onUpdateReturnCustomer);
    on<AddOrUpdateReturnLineItem>(_onAddOrUpdateLineItem);
    on<SetReturnLineItemsForProduct>(_onSetLineItemsForProduct);
    on<RemoveReturnLineItem>(_onRemoveLineItem);
    on<SaveReturn>(_onSaveReturn);
    on<ClearReturnMessages>(_onClearMessages);
  }

  Future<void> _onLoadReturns(
    LoadReturns event,
    Emitter<SalesReturnState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      final loaded = _salesRepository.getLocalReturns();
      emit(state.copyWith(returns: loaded, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  void _onSetDateFilter(
    SetReturnDateFilter event,
    Emitter<SalesReturnState> emit,
  ) {
    emit(state.copyWith(startDate: event.startDate, endDate: event.endDate));
  }

  void _onStartNewReturn(StartNewReturn event, Emitter<SalesReturnState> emit) {
    emit(
      state.copyWith(
        editingReturnId: 'temp_ret_${DateTime.now().millisecondsSinceEpoch}',
        editingDate: DateTime.now(),
        editingCustomer: null,
        editingItems: const [],
        editingReason: '',
        isEditingNew: true,
        errorMessage: null,
        successMessage: null,
      ),
    );
  }

  void _onStartEditReturn(
    StartEditReturn event,
    Emitter<SalesReturnState> emit,
  ) {
    final customers = _salesRepository.getCustomers();
    final customer = customers.firstWhere(
      (c) => c.id == event.salesReturn.customerId,
      orElse: () => Customer(
        id: event.salesReturn.customerId,
        name: event.salesReturn.customerName,
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

    emit(
      state.copyWith(
        editingReturnId: event.salesReturn.id,
        editingDate: event.salesReturn.date,
        editingCustomer: customer,
        editingItems: List.from(event.salesReturn.items),
        editingReason: event.salesReturn.reason,
        isEditingNew: false,
        errorMessage: null,
        successMessage: null,
      ),
    );
  }

  void _onUpdateReturnDate(
    UpdateReturnDate event,
    Emitter<SalesReturnState> emit,
  ) {
    emit(state.copyWith(editingDate: event.date));
  }

  void _onUpdateReturnCustomer(
    UpdateReturnCustomer event,
    Emitter<SalesReturnState> emit,
  ) {
    emit(state.copyWith(editingCustomer: event.customer));
  }

  void _onAddOrUpdateLineItem(
    AddOrUpdateReturnLineItem event,
    Emitter<SalesReturnState> emit,
  ) {
    final items = List<SalesReturnLineItem>.from(state.editingItems);
    final idx = items.indexWhere(
      (line) => line.invoiceLineItem.item.id == event.item.id,
    );

    if (idx >= 0) {
      if (event.quantity <= 0) {
        items.removeAt(idx);
      } else {
        items[idx] = items[idx].copyWith(returnedQuantity: event.quantity);
      }
    } else {
      if (event.quantity > 0) {
        items.add(
          SalesReturnLineItem(
            invoiceLineItem: InvoiceLineItem(
              item: event.item,
              quantity: event.quantity,
              rate: event.item.rate,
              taxPercentage: event.item.taxPercentage,
            ),
            returnedQuantity: event.quantity,
          ),
        );
      }
    }
    emit(state.copyWith(editingItems: items, errorMessage: null));
  }

  void _onSetLineItemsForProduct(
    SetReturnLineItemsForProduct event,
    Emitter<SalesReturnState> emit,
  ) {
    final items = List<SalesReturnLineItem>.from(state.editingItems);
    // Remove existing returns of this item
    items.removeWhere((line) => line.invoiceLineItem.item.id == event.item.id);
    // Add the new returns from specific invoices
    items.addAll(event.lines.where((line) => line.returnedQuantity > 0));
    emit(state.copyWith(editingItems: items, errorMessage: null));
  }

  void _onRemoveLineItem(
    RemoveReturnLineItem event,
    Emitter<SalesReturnState> emit,
  ) {
    final items = List<SalesReturnLineItem>.from(state.editingItems);
    items.removeWhere((line) => line.invoiceLineItem.item.id == event.item.id);
    emit(state.copyWith(editingItems: items));
  }

  Future<void> _onSaveReturn(
    SaveReturn event,
    Emitter<SalesReturnState> emit,
  ) async {
    if (state.editingCustomer == null) {
      emit(state.copyWith(errorMessage: 'Please select a customer'));
      return;
    }
    if (state.editingItems.isEmpty) {
      emit(state.copyWith(errorMessage: 'Please add at least one return item'));
      return;
    }

    emit(state.copyWith(isLoading: true));
    try {
      final isNew = state.isEditingNew;
      final tempId =
          state.editingReturnId ??
          'temp_ret_${DateTime.now().millisecondsSinceEpoch}';

      String creditNoteNum;
      if (isNew) {
        creditNoteNum =
            'CN-TEMP-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
      } else {
        final original = state.returns.firstWhere((r) => r.id == tempId);
        creditNoteNum = original.creditNoteNumber;
      }

      final salesReturn = SalesReturn(
        id: tempId,
        creditNoteNumber: creditNoteNum,
        customerId: state.editingCustomer!.id,
        customerName: state.editingCustomer!.name,
        date: state.editingDate ?? DateTime.now(),
        items: state.editingItems,
        reason: event.reason,
        isPendingSync: true,
      );

      await _salesRepository.saveLocalReturn(salesReturn);

      final syncItem = SyncQueueItem(
        id: tempId,
        type: 'return',
        payload: SalesReturnModel.fromDomain(salesReturn).toJson(),
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      );
      await _salesRepository.enqueueSyncItem(syncItem);

      _syncRepository.triggerSync();

      final updatedReturns = _salesRepository.getLocalReturns();

      emit(
        state.copyWith(
          returns: updatedReturns,
          isLoading: false,
          successMessage: 'Return saved successfully',
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  void _onClearMessages(
    ClearReturnMessages event,
    Emitter<SalesReturnState> emit,
  ) {
    emit(state.copyWith(errorMessage: null, successMessage: null));
  }
}
