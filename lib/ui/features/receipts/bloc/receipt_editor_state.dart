import 'package:equatable/equatable.dart';

import '../../../../domain/models/customer.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../domain/utils/voucher_content_fingerprint.dart';

/// Form-only state for creating/viewing a single receipt voucher.
class ReceiptEditorState extends Equatable {
  final String? editingId;
  final ReceiptVoucher? editingReceipt;
  final DateTime? editingDate;
  final Customer? editingCustomer;
  final double editingAmount;
  final String editingPaymentMode;
  final String editingReferenceNumber;
  final List<PaymentAllocation> editingAllocations;
  final bool isEditingNew;

  final bool isEditorLoading;
  final bool isRefreshing;
  final bool isSaving;
  final String? editorError;

  final String? errorMessage;
  final String? successMessage;

  /// Non-blocking toast (refresh result / offline open); does not pop the route.
  final String? infoMessage;

  const ReceiptEditorState({
    this.editingId,
    this.editingReceipt,
    this.editingDate,
    this.editingCustomer,
    this.editingAmount = 0.0,
    this.editingPaymentMode = 'Cash',
    this.editingReferenceNumber = '',
    this.editingAllocations = const [],
    this.isEditingNew = false,
    this.isEditorLoading = false,
    this.isRefreshing = false,
    this.isSaving = false,
    this.editorError,
    this.errorMessage,
    this.successMessage,
    this.infoMessage,
  });

  /// True when a loaded, synced voucher can be refreshed from Zoho.
  bool get canRefreshFromZoho {
    if (isEditingNew || editorError != null) return false;
    final rec = editingReceipt;
    if (rec == null || rec.isPendingSync) return false;
    final id = editingId ?? rec.id;
    if (id.isEmpty || id.startsWith('temp_pay_')) return false;
    return true;
  }

  /// True when form fields differ from the last loaded [editingReceipt] snapshot.
  bool get isFormDirty {
    final rec = editingReceipt;
    if (rec == null) return false;
    final formFp = VoucherContentFingerprint.receiptForm(
      id: rec.id,
      paymentNumber: rec.paymentNumber,
      customerId: editingCustomer?.id ?? '',
      amount: editingAmount,
      paymentMode: editingPaymentMode,
      referenceNumber: editingReferenceNumber,
      date: editingDate ?? rec.date,
      allocations: editingAllocations,
    );
    return formFp != VoucherContentFingerprint.receipt(rec);
  }

  ReceiptEditorState copyWith({
    String? editingId,
    ReceiptVoucher? editingReceipt,
    DateTime? editingDate,
    Customer? editingCustomer,
    double? editingAmount,
    String? editingPaymentMode,
    String? editingReferenceNumber,
    List<PaymentAllocation>? editingAllocations,
    bool? isEditingNew,
    bool? isEditorLoading,
    bool? isRefreshing,
    bool? isSaving,
    String? editorError,
    String? errorMessage,
    String? successMessage,
    String? infoMessage,
    bool clearMessages = false,
    bool clearEditingCustomer = false,
    bool clearEditingId = false,
    bool clearEditingReceipt = false,
    bool clearEditorError = false,
  }) {
    return ReceiptEditorState(
      editingId:
          clearEditingId ? null : (editingId ?? this.editingId),
      editingReceipt: (clearEditingId || clearEditingReceipt)
          ? null
          : (editingReceipt ?? this.editingReceipt),
      editingDate: editingDate ?? this.editingDate,
      editingCustomer: clearEditingCustomer
          ? null
          : (editingCustomer ?? this.editingCustomer),
      editingAmount: editingAmount ?? this.editingAmount,
      editingPaymentMode: editingPaymentMode ?? this.editingPaymentMode,
      editingReferenceNumber:
          editingReferenceNumber ?? this.editingReferenceNumber,
      editingAllocations: editingAllocations ?? this.editingAllocations,
      isEditingNew: isEditingNew ?? this.isEditingNew,
      isEditorLoading: isEditorLoading ?? this.isEditorLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isSaving: isSaving ?? this.isSaving,
      editorError: clearEditorError ? null : (editorError ?? this.editorError),
      errorMessage: clearMessages ? null : (errorMessage ?? this.errorMessage),
      successMessage:
          clearMessages ? null : (successMessage ?? this.successMessage),
      infoMessage: clearMessages ? null : (infoMessage ?? this.infoMessage),
    );
  }

  @override
  List<Object?> get props => [
    editingId,
    editingReceipt,
    editingDate,
    editingCustomer,
    editingAmount,
    editingPaymentMode,
    editingReferenceNumber,
    editingAllocations,
    isEditingNew,
    isEditorLoading,
    isRefreshing,
    isSaving,
    editorError,
    errorMessage,
    successMessage,
    infoMessage,
  ];
}
