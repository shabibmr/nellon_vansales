import 'package:equatable/equatable.dart';

import '../../../../domain/models/customer.dart';
import '../../../../domain/models/sales_order.dart';

/// Form-only state for creating/editing a single sales order.
class SalesOrderEditorState extends Equatable {
  final String? editingOrderId;

  /// Snapshot of the order opened for edit/view (number, status, etc.).
  final SalesOrder? editingOrder;
  final DateTime? editingDate;
  final DateTime? editingShipmentDate;
  final Customer? editingCustomer;
  final List<OrderLineItem> editingItems;
  final String editingNotes;
  final bool isEditingNew;

  /// True while a saved order is being read from Zoho on open.
  final bool isEditorLoading;

  /// True while save is in progress (kept apart from list loading).
  final bool isSaving;

  /// Set when the Zoho open-read failed; editor shows Retry.
  final String? editorError;

  final String? errorMessage;
  final String? successMessage;

  const SalesOrderEditorState({
    this.editingOrderId,
    this.editingOrder,
    this.editingDate,
    this.editingShipmentDate,
    this.editingCustomer,
    this.editingItems = const [],
    this.editingNotes = '',
    this.isEditingNew = false,
    this.isEditorLoading = false,
    this.isSaving = false,
    this.editorError,
    this.errorMessage,
    this.successMessage,
  });

  /// Whether the open order is already converted to an invoice.
  bool get isConverted => editingOrder?.isConverted ?? false;

  SalesOrderEditorState copyWith({
    String? editingOrderId,
    SalesOrder? editingOrder,
    DateTime? editingDate,
    DateTime? editingShipmentDate,
    Customer? editingCustomer,
    List<OrderLineItem>? editingItems,
    String? editingNotes,
    bool? isEditingNew,
    bool? isEditorLoading,
    bool? isSaving,
    String? editorError,
    String? errorMessage,
    String? successMessage,
    bool clearMessages = false,
    bool clearEditingCustomer = false,
    bool clearEditingOrderId = false,
    bool clearEditingOrder = false,
    bool clearEditorError = false,
  }) {
    return SalesOrderEditorState(
      editingOrderId: clearEditingOrderId
          ? null
          : (editingOrderId ?? this.editingOrderId),
      editingOrder: (clearEditingOrderId || clearEditingOrder)
          ? null
          : (editingOrder ?? this.editingOrder),
      editingDate: editingDate ?? this.editingDate,
      editingShipmentDate: editingShipmentDate ?? this.editingShipmentDate,
      editingCustomer: clearEditingCustomer
          ? null
          : (editingCustomer ?? this.editingCustomer),
      editingItems: editingItems ?? this.editingItems,
      editingNotes: editingNotes ?? this.editingNotes,
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
    editingOrderId,
    editingOrder,
    editingDate,
    editingShipmentDate,
    editingCustomer,
    editingItems,
    editingNotes,
    isEditingNew,
    isEditorLoading,
    isSaving,
    editorError,
    errorMessage,
    successMessage,
  ];
}
