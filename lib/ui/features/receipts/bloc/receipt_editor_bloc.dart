// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/models/receipt_voucher_model.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/services/document_number_service.dart';
import '../../../../data/services/error_classification.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/open_invoice.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../domain/utils/voucher_content_fingerprint.dart';
import 'receipt_editor_event.dart';
import 'receipt_editor_state.dart';

/// Manages a single receipt-voucher form: open, auto-allocation, save, enqueue sync.
class ReceiptEditorBloc
    extends Bloc<ReceiptEditorEvent, ReceiptEditorState> {
  final SalesRepository _salesRepository;
  final SyncRepository _syncRepository;
  final DocumentNumberService _documentNumberService;

  ReceiptEditorBloc({
    required SalesRepository salesRepository,
    required SyncRepository syncRepository,
    required DocumentNumberService documentNumberService,
  }) : _salesRepository = salesRepository,
       _syncRepository = syncRepository,
       _documentNumberService = documentNumberService,
       super(const ReceiptEditorState()) {
    on<StartNewReceipt>(_onStartNewReceipt);
    on<OpenReceiptVoucher>(_onOpenReceiptVoucher);
    on<RetryLoadReceiptVoucher>(_onRetryLoadReceiptVoucher);
    on<RefreshReceiptVoucherFromZoho>(_onRefreshReceiptVoucherFromZoho);
    on<SetEditingReceiptCustomer>(_onSetCustomer);
    on<SetEditingAmount>(_onSetAmount);
    on<SetEditingPaymentMode>(_onSetPaymentMode);
    on<SetEditingReference>(_onSetReference);
    on<SetEditingReceiptDate>(_onSetDate);
    on<UpdateReceiptAllocations>(_onUpdateAllocations);
    on<SaveReceipt>(_onSaveReceipt);
    on<ClearReceiptEditorMessages>(_onClearMessages);
  }

  static bool _isLocalReceiptId(String id) => id.startsWith('temp_pay_');

  void _onStartNewReceipt(
    StartNewReceipt event,
    Emitter<ReceiptEditorState> emit,
  ) {
    final now = DateTime.now();
    emit(
      state.copyWith(
        clearEditingId: true,
        clearEditingCustomer: event.customer == null,
        clearMessages: true,
        editingDate: now,
        editingAmount: 0.0,
        editingPaymentMode: 'Cash',
        editingReferenceNumber: '',
        editingAllocations: const [],
        isEditingNew: true,
        isEditorLoading: false,
        isSaving: false,
        clearEditorError: true,
        editingCustomer: event.customer,
      ),
    );
  }

  Future<void> _onOpenReceiptVoucher(
    OpenReceiptVoucher event,
    Emitter<ReceiptEditorState> emit,
  ) async {
    if (event.receipt.isPendingSync || _isLocalReceiptId(event.receipt.id)) {
      emit(_openedFrom(event.receipt));
      return;
    }

    emit(
      state.copyWith(
        editingId: event.receipt.id,
        clearEditingReceipt: true,
        clearEditingCustomer: true,
        clearMessages: true,
        clearEditorError: true,
        editingAllocations: const [],
        isEditingNew: false,
        isEditorLoading: true,
        isSaving: false,
      ),
    );
    await _loadEditingReceiptFromZoho(event.receipt.id, emit);
  }

  Future<void> _onRetryLoadReceiptVoucher(
    RetryLoadReceiptVoucher event,
    Emitter<ReceiptEditorState> emit,
  ) async {
    final receiptId = state.editingId;
    if (receiptId == null || receiptId.isEmpty) return;
    emit(state.copyWith(isEditorLoading: true, clearEditorError: true));
    await _loadEditingReceiptFromZoho(receiptId, emit);
  }

  Future<void> _onRefreshReceiptVoucherFromZoho(
    RefreshReceiptVoucherFromZoho event,
    Emitter<ReceiptEditorState> emit,
  ) async {
    final receiptId = state.editingId ?? state.editingReceipt?.id;
    if (receiptId == null ||
        receiptId.isEmpty ||
        _isLocalReceiptId(receiptId) ||
        state.isEditorLoading ||
        state.isRefreshing ||
        state.editingReceipt == null) {
      return;
    }
    emit(
      state.copyWith(
        isRefreshing: true,
        clearEditorError: true,
        clearMessages: true,
      ),
    );
    await _loadEditingReceiptFromZoho(receiptId, emit, isRefresh: true);
  }

  Future<void> _loadEditingReceiptFromZoho(
    String receiptId,
    Emitter<ReceiptEditorState> emit, {
    bool isRefresh = false,
  }) async {
    final previous = isRefresh ? state.editingReceipt : null;
    final wasDirty = isRefresh && state.isFormDirty;

    ReceiptVoucher? fetched;
    try {
      fetched = await _salesRepository.fetchReceiptById(
        receiptId,
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
        fetched = await _salesRepository.fetchReceiptById(
          receiptId,
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
        ReceiptVoucher? local;
        try {
          local = await _salesRepository.fetchReceiptById(
            receiptId,
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
            errorMessage: 'This receipt voucher was not found in Zoho Books.',
          ),
        );
      } else {
        emit(
          state.copyWith(
            isEditorLoading: false,
            isRefreshing: false,
            editorError: 'This receipt voucher was not found in Zoho Books.',
          ),
        );
      }
      return;
    }

    final opened = _openedFrom(fetched);
    if (isRefresh) {
      final contentUnchanged = previous != null &&
          VoucherContentFingerprint.receipt(previous) ==
              VoucherContentFingerprint.receipt(fetched);
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

  ReceiptEditorState _openedFrom(ReceiptVoucher rec) {
    final customer = _customerForId(rec.customerId, rec.customerName);

    return state.copyWith(
      editingId: rec.id,
      editingReceipt: rec.copyWith(),
      editingDate: rec.date,
      editingCustomer: customer,
      editingAmount: rec.amount,
      editingPaymentMode: rec.paymentMode,
      editingReferenceNumber: rec.referenceNumber,
      editingAllocations: List.of(rec.allocations),
      isEditingNew: false,
      isEditorLoading: false,
      isSaving: false,
      clearMessages: true,
      clearEditorError: true,
    );
  }

  Future<void> _onSetCustomer(
    SetEditingReceiptCustomer event,
    Emitter<ReceiptEditorState> emit,
  ) async {
    try {
      await _salesRepository.fetchRemoteOpenInvoices(
        customerId: event.customer.id,
      );
    } catch (_) {
      // Safe swallow: fallback to cached local open invoices when offline
    }

    final allocations = _autoAllocate(event.customer.id, state.editingAmount);
    emit(
      state.copyWith(
        editingCustomer: event.customer,
        editingAllocations: allocations,
        clearMessages: true,
      ),
    );
  }

  void _onSetAmount(SetEditingAmount event, Emitter<ReceiptEditorState> emit) {
    final customerId = state.editingCustomer?.id;
    final allocations = customerId != null
        ? _autoAllocate(customerId, event.amount)
        : const <PaymentAllocation>[];
    emit(
      state.copyWith(
        editingAmount: event.amount,
        editingAllocations: allocations,
        clearMessages: true,
      ),
    );
  }

  void _onSetPaymentMode(
    SetEditingPaymentMode event,
    Emitter<ReceiptEditorState> emit,
  ) {
    emit(state.copyWith(editingPaymentMode: event.mode));
  }

  void _onSetReference(
    SetEditingReference event,
    Emitter<ReceiptEditorState> emit,
  ) {
    emit(state.copyWith(editingReferenceNumber: event.reference));
  }

  void _onSetDate(
    SetEditingReceiptDate event,
    Emitter<ReceiptEditorState> emit,
  ) {
    emit(state.copyWith(editingDate: event.date));
  }

  void _onUpdateAllocations(
    UpdateReceiptAllocations event,
    Emitter<ReceiptEditorState> emit,
  ) {
    emit(state.copyWith(editingAllocations: event.allocations));
  }

  List<PaymentAllocation> _autoAllocate(String customerId, double amount) {
    if (amount <= 0) return const [];
    try {
      final openInvoices = _salesRepository.getOpenInvoices(
        customerId: customerId,
      );
      final sortedInvoices = List<OpenInvoice>.from(openInvoices)
        ..sort((a, b) => a.date.compareTo(b.date));

      final List<PaymentAllocation> allocations = [];
      double remainingAmount = amount;

      for (final invoice in sortedInvoices) {
        if (remainingAmount <= 0) break;
        final balance = invoice.balance;
        if (balance <= 0) continue;

        final allocated = remainingAmount >= balance ? balance : remainingAmount;
        allocations.add(
          PaymentAllocation(
            invoiceId: invoice.invoiceId,
            invoiceNumber: invoice.invoiceNumber,
            amountApplied: double.parse(allocated.toStringAsFixed(2)),
          ),
        );
        remainingAmount -= allocated;
        remainingAmount = double.parse(remainingAmount.toStringAsFixed(2));
      }
      return allocations;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _onSaveReceipt(
    SaveReceipt event,
    Emitter<ReceiptEditorState> emit,
  ) async {
    if (state.editingCustomer == null) {
      emit(state.copyWith(errorMessage: 'Please select a customer'));
      return;
    }
    if (state.editingAmount <= 0) {
      emit(state.copyWith(errorMessage: 'Please enter a valid payment amount'));
      return;
    }

    emit(state.copyWith(isSaving: true, clearMessages: true));
    try {
      final isNew = state.isEditingNew;
      final tempId =
          state.editingId ??
          'temp_pay_${DateTime.now().millisecondsSinceEpoch}';
      final ts = DateTime.now().millisecondsSinceEpoch.toString();

      String paymentNum;
      String refNum;
      if (isNew) {
        paymentNum = await _documentNumberService.nextNumber(DocType.receipt);
        refNum = state.editingReferenceNumber.isNotEmpty
            ? state.editingReferenceNumber
            : 'REF-VAN-${ts.substring(10)}';
      } else {
        final original = state.editingReceipt;
        if (original == null || original.id != tempId) {
          emit(
            state.copyWith(
              isSaving: false,
              errorMessage: 'Could not find the receipt being edited',
            ),
          );
          return;
        }
        paymentNum = original.paymentNumber;
        refNum = state.editingReferenceNumber.isNotEmpty
            ? state.editingReferenceNumber
            : original.referenceNumber;
      }

      final voucher = ReceiptVoucher(
        id: tempId,
        paymentNumber: paymentNum,
        customerId: state.editingCustomer!.id,
        customerName: state.editingCustomer!.name,
        allocations: state.editingAllocations,
        amount: state.editingAmount,
        paymentMode: state.editingPaymentMode,
        referenceNumber: refNum,
        date: state.editingDate ?? DateTime.now(),
        isPendingSync: true,
      );

      await _salesRepository.saveLocalReceipt(voucher);

      final syncItem = SyncQueueItem(
        id: tempId,
        type: 'receipt',
        payload: ReceiptVoucherModel.fromDomain(voucher).toJson(),
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      );
      await _salesRepository.enqueueSyncItem(syncItem);

      unawaited(_syncRepository.triggerSync());

      emit(
        state.copyWith(
          editingId: voucher.id,
          editingReceipt: voucher,
          isEditingNew: false,
          isSaving: false,
          successMessage: 'Receipt saved successfully',
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
    ClearReceiptEditorMessages event,
    Emitter<ReceiptEditorState> emit,
  ) {
    emit(state.copyWith(clearMessages: true));
  }
}
