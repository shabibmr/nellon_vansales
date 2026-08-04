// ignore_for_file: prefer_initializing_formals
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/models/sales_return_model.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/services/document_number_service.dart';
import '../../../../data/services/error_classification.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import 'sales_return_editor_event.dart';
import 'sales_return_editor_state.dart';

/// Manages a single sales-return form: open, edit lines, save, enqueue sync.
class SalesReturnEditorBloc
    extends Bloc<SalesReturnEditorEvent, SalesReturnEditorState> {
  final SalesRepository _salesRepository;
  final SyncRepository _syncRepository;
  final DocumentNumberService _documentNumberService;

  SalesReturnEditorBloc({
    required SalesRepository salesRepository,
    required SyncRepository syncRepository,
    required DocumentNumberService documentNumberService,
  }) : _salesRepository = salesRepository,
       _syncRepository = syncRepository,
       _documentNumberService = documentNumberService,
       super(const SalesReturnEditorState()) {
    on<StartNewReturn>(_onStartNewReturn);
    on<OpenSalesReturn>(_onOpenSalesReturn);
    on<RetryLoadSalesReturn>(_onRetryLoadSalesReturn);
    on<UpdateReturnDate>(_onUpdateReturnDate);
    on<UpdateReturnCustomer>(_onUpdateReturnCustomer);
    on<AddOrUpdateReturnLineItem>(_onAddOrUpdateLineItem);
    on<SetReturnLineItemsForProduct>(_onSetLineItemsForProduct);
    on<RemoveReturnLineItem>(_onRemoveLineItem);
    on<SaveReturn>(_onSaveReturn);
    on<ClearSalesReturnEditorMessages>(_onClearMessages);
  }

  static bool _isLocalReturnId(String id) => id.startsWith('temp_ret_');

  void _onStartNewReturn(
    StartNewReturn event,
    Emitter<SalesReturnEditorState> emit,
  ) {
    final now = DateTime.now();
    emit(
      state.copyWith(
        clearEditingReturnId: true,
        clearEditingCustomer: event.customer == null,
        clearMessages: true,
        editingDate: now,
        editingItems: const [],
        editingReason: '',
        isEditingNew: true,
        isEditorLoading: false,
        isSaving: false,
        clearEditorError: true,
        editingCustomer: event.customer,
      ),
    );
  }

  Future<void> _onOpenSalesReturn(
    OpenSalesReturn event,
    Emitter<SalesReturnEditorState> emit,
  ) async {
    if (event.salesReturn.isPendingSync || _isLocalReturnId(event.salesReturn.id)) {
      emit(_openedFrom(event.salesReturn));
      return;
    }

    emit(
      state.copyWith(
        editingReturnId: event.salesReturn.id,
        clearEditingReturn: true,
        clearEditingCustomer: true,
        clearMessages: true,
        clearEditorError: true,
        editingItems: const [],
        editingReason: '',
        isEditingNew: false,
        isEditorLoading: true,
        isSaving: false,
      ),
    );
    await _loadEditingReturnFromZoho(event.salesReturn.id, emit);
  }

  Future<void> _onRetryLoadSalesReturn(
    RetryLoadSalesReturn event,
    Emitter<SalesReturnEditorState> emit,
  ) async {
    final returnId = state.editingReturnId;
    if (returnId == null || returnId.isEmpty) return;
    emit(state.copyWith(isEditorLoading: true, clearEditorError: true));
    await _loadEditingReturnFromZoho(returnId, emit);
  }

  Future<void> _loadEditingReturnFromZoho(
    String returnId,
    Emitter<SalesReturnEditorState> emit,
  ) async {
    try {
      final fetched = await _salesRepository.fetchSalesReturnById(returnId);
      if (fetched == null) {
        emit(
          state.copyWith(
            isEditorLoading: false,
            editorError: 'This sales return was not found in Zoho Books.',
          ),
        );
        return;
      }
      emit(_openedFrom(fetched));
    } catch (e) {
      emit(
        state.copyWith(
          isEditorLoading: false,
          editorError: humanizeSyncError(e),
        ),
      );
    }
  }

  Customer _customerForId(String customerId, String nameFallback) {
    for (final c in _salesRepository.getCustomers()) {
      if (c.id == customerId) return c;
    }
    return Customer(
      id: customerId,
      name: nameFallback,
      companyName: nameFallback,
      email: '',
      phone: '',
      address: '',
      outstandingBalance: 0,
      creditLimit: 0,
      routeId: '',
      sequence: 0,
    );
  }

  SalesReturnEditorState _openedFrom(SalesReturn ret) {
    final customer = _customerForId(ret.customerId, ret.customerName);

    return state.copyWith(
      editingReturnId: ret.id,
      editingReturn: ret.copyWith(),
      editingDate: ret.date,
      editingCustomer: customer,
      editingItems: List.of(ret.items),
      editingReason: ret.reason,
      isEditingNew: false,
      isEditorLoading: false,
      isSaving: false,
      clearMessages: true,
      clearEditorError: true,
    );
  }

  void _onUpdateReturnDate(
    UpdateReturnDate event,
    Emitter<SalesReturnEditorState> emit,
  ) {
    emit(state.copyWith(editingDate: event.date));
  }

  void _onUpdateReturnCustomer(
    UpdateReturnCustomer event,
    Emitter<SalesReturnEditorState> emit,
  ) {
    emit(state.copyWith(editingCustomer: event.customer));
  }

  void _onAddOrUpdateLineItem(
    AddOrUpdateReturnLineItem event,
    Emitter<SalesReturnEditorState> emit,
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
    emit(state.copyWith(editingItems: items, clearMessages: true));
  }

  void _onSetLineItemsForProduct(
    SetReturnLineItemsForProduct event,
    Emitter<SalesReturnEditorState> emit,
  ) {
    final items = List<SalesReturnLineItem>.from(state.editingItems);
    items.removeWhere((line) => line.invoiceLineItem.item.id == event.item.id);
    items.addAll(event.lines.where((line) => line.returnedQuantity > 0));
    emit(state.copyWith(editingItems: items, clearMessages: true));
  }

  void _onRemoveLineItem(
    RemoveReturnLineItem event,
    Emitter<SalesReturnEditorState> emit,
  ) {
    final items = List<SalesReturnLineItem>.from(state.editingItems);
    items.removeWhere((line) => line.invoiceLineItem.item.id == event.item.id);
    emit(state.copyWith(editingItems: items));
  }

  Future<void> _onSaveReturn(
    SaveReturn event,
    Emitter<SalesReturnEditorState> emit,
  ) async {
    if (state.editingCustomer == null) {
      emit(state.copyWith(errorMessage: 'Please select a customer'));
      return;
    }
    if (state.editingItems.isEmpty) {
      emit(state.copyWith(errorMessage: 'Please add at least one return item'));
      return;
    }

    emit(state.copyWith(isSaving: true, clearMessages: true));
    try {
      final isNew = state.isEditingNew;
      final tempId =
          state.editingReturnId ??
          'temp_ret_${DateTime.now().millisecondsSinceEpoch}';

      String creditNoteNum;
      if (isNew) {
        creditNoteNum = await _documentNumberService.nextNumber(
          DocType.creditNote,
        );
      } else {
        final original = state.editingReturn;
        if (original == null || original.id != tempId) {
          emit(
            state.copyWith(
              isSaving: false,
              errorMessage: 'Could not find the return being edited',
            ),
          );
          return;
        }
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

      emit(
        state.copyWith(
          editingReturnId: salesReturn.id,
          editingReturn: salesReturn,
          isEditingNew: false,
          isSaving: false,
          successMessage: 'Return saved successfully',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: humanizeSyncError(e),
        ),
      );
    }
  }

  void _onClearMessages(
    ClearSalesReturnEditorMessages event,
    Emitter<SalesReturnEditorState> emit,
  ) {
    emit(state.copyWith(clearMessages: true));
  }
}
