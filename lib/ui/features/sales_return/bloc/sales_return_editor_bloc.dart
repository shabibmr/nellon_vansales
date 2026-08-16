// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/services/document_number_service.dart';
import '../../../../data/services/error_classification.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../../domain/models/submit_result.dart';
import '../../../../domain/repositories/customer_repository.dart';
import '../../../../domain/repositories/sales_return_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../domain/utils/voucher_content_fingerprint.dart';
import 'sales_return_editor_event.dart';
import 'sales_return_editor_state.dart';

/// Manages a single sales-return form: open, edit lines, save, enqueue sync.
class SalesReturnEditorBloc
    extends Bloc<SalesReturnEditorEvent, SalesReturnEditorState> {
  final SalesReturnRepository _salesReturnRepository;
  final CustomerRepository _customerRepository;
  // ignore: unused_field — kept so existing BlocProvider wiring stays unchanged
  final SyncRepository _syncRepository;
  final DocumentNumberService _documentNumberService;

  SalesReturnEditorBloc({
    required SalesReturnRepository salesReturnRepository,
    required CustomerRepository customerRepository,
    required SyncRepository syncRepository,
    required DocumentNumberService documentNumberService,
  }) : _salesReturnRepository = salesReturnRepository,
       _customerRepository = customerRepository,
       _syncRepository = syncRepository,
       _documentNumberService = documentNumberService,
       super(const SalesReturnEditorState()) {
    on<StartNewReturn>(_onStartNewReturn);
    on<OpenSalesReturn>(_onOpenSalesReturn);
    on<RetryLoadSalesReturn>(_onRetryLoadSalesReturn);
    on<RefreshSalesReturnFromZoho>(_onRefreshSalesReturnFromZoho);
    on<UpdateReturnReason>(_onUpdateReturnReason);
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
    if (event.salesReturn.isPendingSync) {
      emit(_openedFrom(event.salesReturn));
      return;
    }
    final remoteId = event.salesReturn.zohoCreditNoteId ?? event.salesReturn.id;
    if (_isLocalReturnId(remoteId)) {
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
    await _loadEditingReturnFromZoho(remoteId, emit);
  }

  Future<void> _onRetryLoadSalesReturn(
    RetryLoadSalesReturn event,
    Emitter<SalesReturnEditorState> emit,
  ) async {
    final returnId = _remoteReturnIdForLoad();
    if (returnId == null || returnId.isEmpty) return;
    emit(state.copyWith(isEditorLoading: true, clearEditorError: true));
    await _loadEditingReturnFromZoho(returnId, emit);
  }

  Future<void> _onRefreshSalesReturnFromZoho(
    RefreshSalesReturnFromZoho event,
    Emitter<SalesReturnEditorState> emit,
  ) async {
    final returnId = _remoteReturnIdForLoad();
    if (returnId == null ||
        returnId.isEmpty ||
        _isLocalReturnId(returnId) ||
        state.isEditorLoading ||
        state.isRefreshing ||
        state.editingReturn == null) {
      return;
    }
    emit(
      state.copyWith(
        isRefreshing: true,
        clearEditorError: true,
        clearMessages: true,
      ),
    );
    await _loadEditingReturnFromZoho(
      returnId,
      emit,
      isRefresh: true,
      forceDirty: event.forceDirty,
    );
  }

  String? _remoteReturnIdForLoad() {
    final zohoId = state.editingReturn?.zohoCreditNoteId;
    if (zohoId != null && zohoId.isNotEmpty) return zohoId;
    return state.editingReturnId ?? state.editingReturn?.id;
  }

  void _onUpdateReturnReason(
    UpdateReturnReason event,
    Emitter<SalesReturnEditorState> emit,
  ) {
    emit(state.copyWith(editingReason: event.reason));
  }

  Future<void> _loadEditingReturnFromZoho(
    String returnId,
    Emitter<SalesReturnEditorState> emit, {
    bool isRefresh = false,
    bool forceDirty = false,
  }) async {
    final previous = isRefresh ? state.editingReturn : null;
    final wasDirty = isRefresh && (state.isFormDirty || forceDirty);

    SalesReturn? fetched;
    try {
      fetched = await _salesReturnRepository.fetchSalesReturnById(
        returnId,
        forceRemote: true,
        allowOfflineFallback: false,
      );
    } catch (e) {
      if (isRefresh) {
        emit(
          state.copyWith(
            isRefreshing: false,
            errorMessage: humanizeSyncError(e),
          ),
        );
        return;
      }
      try {
        fetched = await _salesReturnRepository.fetchSalesReturnById(
          returnId,
          forceRemote: false,
        );
      } catch (_) {
        fetched = null;
      }
      if (fetched != null) {
        emit(
          _openedFrom(fetched).copyWith(
            infoMessage: 'Showing offline copy',
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          isEditorLoading: false,
          isRefreshing: false,
          editorError: humanizeSyncError(e),
        ),
      );
      return;
    }

    if (fetched == null) {
      if (!isRefresh) {
        SalesReturn? local;
        try {
          local = await _salesReturnRepository.fetchSalesReturnById(
            returnId,
            forceRemote: false,
          );
        } catch (_) {
          local = null;
        }
        if (local != null) {
          emit(
            _openedFrom(local).copyWith(
              infoMessage: 'Not found in Zoho — showing local copy',
            ),
          );
          return;
        }
      }
      if (isRefresh && previous != null) {
        emit(
          state.copyWith(
            isRefreshing: false,
            errorMessage: 'This sales return was not found in Zoho Books.',
          ),
        );
      } else {
        emit(
          state.copyWith(
            isEditorLoading: false,
            isRefreshing: false,
            editorError: 'This sales return was not found in Zoho Books.',
          ),
        );
      }
      return;
    }

    final opened = _openedFrom(fetched);
    if (isRefresh) {
      final contentUnchanged = previous != null &&
          VoucherContentFingerprint.salesReturn(previous) ==
              VoucherContentFingerprint.salesReturn(fetched);
      emit(
        opened.copyWith(
          isRefreshing: false,
          infoMessage: (wasDirty || !contentUnchanged)
              ? 'Updated from Zoho Books'
              : 'Already up to date',
        ),
      );
    } else {
      emit(opened);
    }
  }

  Customer _customerForId(String customerId, String nameFallback) {
    for (final c in _customerRepository.getCustomers()) {
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

      if (isTempCustomerId(state.editingCustomer!.id)) {
        emit(
          state.copyWith(
            isSaving: false,
            errorMessage: 'Customer must sync to Zoho before a return',
          ),
        );
        return;
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

      final result = await _salesReturnRepository.submitSalesReturn(salesReturn);

      emit(
        state.copyWith(
          editingReturnId: salesReturn.id,
          editingReturn: salesReturn,
          isEditingNew: false,
          isSaving: false,
          successMessage: result.message('Return saved successfully'),
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
