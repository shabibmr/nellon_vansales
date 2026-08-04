import 'package:equatable/equatable.dart';

import '../../../../domain/models/customer.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/models/sales_order.dart';

/// Form-only state for creating/viewing a single sales invoice.
class SalesInvoiceEditorState extends Equatable {
  final String? editingInvoiceId;
  final SalesInvoice? editingInvoice;
  final DateTime? editingDate;
  final Customer? editingCustomer;
  final List<InvoiceLineItem> editingItems;
  final String editingNotes;
  final bool isEditingNew;

  /// When creating an invoice by converting a sales order.
  final String? sourceOrderId;
  final SalesOrder? sourceOrder;

  final bool isEditorLoading;
  final bool isSaving;
  final String? editorError;

  final String? errorMessage;
  final String? successMessage;

  const SalesInvoiceEditorState({
    this.editingInvoiceId,
    this.editingInvoice,
    this.editingDate,
    this.editingCustomer,
    this.editingItems = const [],
    this.editingNotes = '',
    this.isEditingNew = false,
    this.sourceOrderId,
    this.sourceOrder,
    this.isEditorLoading = false,
    this.isSaving = false,
    this.editorError,
    this.errorMessage,
    this.successMessage,
  });

  SalesInvoiceEditorState copyWith({
    String? editingInvoiceId,
    SalesInvoice? editingInvoice,
    DateTime? editingDate,
    Customer? editingCustomer,
    List<InvoiceLineItem>? editingItems,
    String? editingNotes,
    bool? isEditingNew,
    String? sourceOrderId,
    SalesOrder? sourceOrder,
    bool? isEditorLoading,
    bool? isSaving,
    String? editorError,
    String? errorMessage,
    String? successMessage,
    bool clearMessages = false,
    bool clearEditingCustomer = false,
    bool clearEditingInvoiceId = false,
    bool clearEditingInvoice = false,
    bool clearEditorError = false,
    bool clearSource = false,
  }) {
    return SalesInvoiceEditorState(
      editingInvoiceId: clearEditingInvoiceId
          ? null
          : (editingInvoiceId ?? this.editingInvoiceId),
      editingInvoice: (clearEditingInvoiceId || clearEditingInvoice)
          ? null
          : (editingInvoice ?? this.editingInvoice),
      editingDate: editingDate ?? this.editingDate,
      editingCustomer: clearEditingCustomer
          ? null
          : (editingCustomer ?? this.editingCustomer),
      editingItems: editingItems ?? this.editingItems,
      editingNotes: editingNotes ?? this.editingNotes,
      isEditingNew: isEditingNew ?? this.isEditingNew,
      sourceOrderId:
          clearSource ? null : (sourceOrderId ?? this.sourceOrderId),
      sourceOrder: clearSource ? null : (sourceOrder ?? this.sourceOrder),
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
    editingInvoiceId,
    editingInvoice,
    editingDate,
    editingCustomer,
    editingItems,
    editingNotes,
    isEditingNew,
    sourceOrderId,
    sourceOrder,
    isEditorLoading,
    isSaving,
    editorError,
    errorMessage,
    successMessage,
  ];
}
