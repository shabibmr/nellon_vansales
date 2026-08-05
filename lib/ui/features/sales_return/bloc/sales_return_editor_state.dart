import 'package:equatable/equatable.dart';

import '../../../../domain/models/customer.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../../domain/utils/voucher_content_fingerprint.dart';

/// Form-only state for creating/viewing a single sales return (credit note).
class SalesReturnEditorState extends Equatable {
  final String? editingReturnId;
  final SalesReturn? editingReturn;
  final DateTime? editingDate;
  final Customer? editingCustomer;
  final List<SalesReturnLineItem> editingItems;
  final String editingReason;
  final bool isEditingNew;

  final bool isEditorLoading;
  final bool isRefreshing;
  final bool isSaving;
  final String? editorError;

  final String? errorMessage;
  final String? successMessage;

  /// Non-blocking toast (refresh result / offline open); does not pop the route.
  final String? infoMessage;

  const SalesReturnEditorState({
    this.editingReturnId,
    this.editingReturn,
    this.editingDate,
    this.editingCustomer,
    this.editingItems = const [],
    this.editingReason = '',
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
    final ret = editingReturn;
    if (ret == null || ret.isPendingSync) return false;
    final id = editingReturnId ?? ret.id;
    if (id.isEmpty || id.startsWith('temp_ret_')) return false;
    return true;
  }

  /// True when form fields differ from the last loaded [editingReturn] snapshot.
  bool get isFormDirty {
    final ret = editingReturn;
    if (ret == null) return false;
    final formFp = VoucherContentFingerprint.salesReturnForm(
      id: ret.id,
      creditNoteNumber: ret.creditNoteNumber,
      customerId: editingCustomer?.id ?? '',
      date: editingDate ?? ret.date,
      reason: editingReason,
      items: editingItems,
    );
    return formFp != VoucherContentFingerprint.salesReturn(ret);
  }

  SalesReturnEditorState copyWith({
    String? editingReturnId,
    SalesReturn? editingReturn,
    DateTime? editingDate,
    Customer? editingCustomer,
    List<SalesReturnLineItem>? editingItems,
    String? editingReason,
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
    bool clearEditingReturnId = false,
    bool clearEditingReturn = false,
    bool clearEditorError = false,
  }) {
    return SalesReturnEditorState(
      editingReturnId: clearEditingReturnId
          ? null
          : (editingReturnId ?? this.editingReturnId),
      editingReturn: (clearEditingReturnId || clearEditingReturn)
          ? null
          : (editingReturn ?? this.editingReturn),
      editingDate: editingDate ?? this.editingDate,
      editingCustomer: clearEditingCustomer
          ? null
          : (editingCustomer ?? this.editingCustomer),
      editingItems: editingItems ?? this.editingItems,
      editingReason: editingReason ?? this.editingReason,
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
    editingReturnId,
    editingReturn,
    editingDate,
    editingCustomer,
    editingItems,
    editingReason,
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
