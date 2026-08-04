import 'package:equatable/equatable.dart';

import '../../../../domain/models/customer.dart';
import '../../../../domain/models/receipt_voucher.dart';

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
  final bool isSaving;
  final String? editorError;

  final String? errorMessage;
  final String? successMessage;

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
    this.isSaving = false,
    this.editorError,
    this.errorMessage,
    this.successMessage,
  });

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
    bool? isSaving,
    String? editorError,
    String? errorMessage,
    String? successMessage,
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
      isSaving: isSaving ?? this.isSaving,
      editorError: clearEditorError ? null : (editorError ?? this.editorError),
      errorMessage: clearMessages ? null : (errorMessage ?? this.errorMessage),
      successMessage:
          clearMessages ? null : (successMessage ?? this.successMessage),
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
    isSaving,
    editorError,
    errorMessage,
    successMessage,
  ];
}
