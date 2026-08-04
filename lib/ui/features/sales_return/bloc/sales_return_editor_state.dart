import 'package:equatable/equatable.dart';

import '../../../../domain/models/customer.dart';
import '../../../../domain/models/sales_return.dart';

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
  final bool isSaving;
  final String? editorError;

  final String? errorMessage;
  final String? successMessage;

  const SalesReturnEditorState({
    this.editingReturnId,
    this.editingReturn,
    this.editingDate,
    this.editingCustomer,
    this.editingItems = const [],
    this.editingReason = '',
    this.isEditingNew = false,
    this.isEditorLoading = false,
    this.isSaving = false,
    this.editorError,
    this.errorMessage,
    this.successMessage,
  });

  SalesReturnEditorState copyWith({
    String? editingReturnId,
    SalesReturn? editingReturn,
    DateTime? editingDate,
    Customer? editingCustomer,
    List<SalesReturnLineItem>? editingItems,
    String? editingReason,
    bool? isEditingNew,
    bool? isEditorLoading,
    bool? isSaving,
    String? editorError,
    String? errorMessage,
    String? successMessage,
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
      isSaving: isSaving ?? this.isSaving,
      editorError: clearEditorError ? null : (editorError ?? this.editorError),
      errorMessage: clearMessages ? null : (errorMessage ?? this.errorMessage),
      successMessage:
          clearMessages ? null : (successMessage ?? this.successMessage),
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
    isSaving,
    editorError,
    errorMessage,
    successMessage,
  ];
}
