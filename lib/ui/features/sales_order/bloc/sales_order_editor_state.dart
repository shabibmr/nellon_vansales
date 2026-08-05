import 'package:equatable/equatable.dart';

import '../../../../domain/models/customer.dart';
import '../../../../domain/models/sales_order.dart';
import '../../../../domain/utils/voucher_content_fingerprint.dart';

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

  /// Soft in-place refresh (form stays visible).
  final bool isRefreshing;

  /// True while save is in progress (kept apart from list loading).
  final bool isSaving;

  /// Set when the Zoho open-read failed; editor shows Retry.
  final String? editorError;

  final String? errorMessage;
  final String? successMessage;

  /// Non-blocking toast (refresh result / offline open); does not pop the route.
  final String? infoMessage;

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
    this.isRefreshing = false,
    this.isSaving = false,
    this.editorError,
    this.errorMessage,
    this.successMessage,
    this.infoMessage,
  });

  /// Whether the open order is already converted to an invoice.
  bool get isConverted => editingOrder?.isConverted ?? false;

  /// True when a loaded, synced voucher can be refreshed from Zoho.
  bool get canRefreshFromZoho {
    if (isEditingNew || editorError != null) return false;
    final order = editingOrder;
    if (order == null || order.isPendingSync) return false;
    final zohoId = order.zohoOrderId;
    if (zohoId != null && zohoId.isNotEmpty) return true;
    final id = editingOrderId ?? order.id;
    if (id.isEmpty || id.startsWith('temp_so_')) return false;
    return true;
  }

  /// True when form fields differ from the last loaded [editingOrder] snapshot.
  bool get isFormDirty {
    final order = editingOrder;
    if (order == null) return false;
    final formFp = VoucherContentFingerprint.salesOrderForm(
      id: order.id,
      orderNumber: order.orderNumber,
      customerId: editingCustomer?.id ?? '',
      date: editingDate ?? order.date,
      shipmentDate: editingShipmentDate ?? order.shipmentDate,
      notes: editingNotes,
      statusName: order.status.name,
      items: editingItems,
    );
    return formFp != VoucherContentFingerprint.salesOrder(order);
  }

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
    bool? isRefreshing,
    bool? isSaving,
    String? editorError,
    String? errorMessage,
    String? successMessage,
    String? infoMessage,
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
    editingOrderId,
    editingOrder,
    editingDate,
    editingShipmentDate,
    editingCustomer,
    editingItems,
    editingNotes,
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
