import 'dart:typed_data';
import 'package:equatable/equatable.dart';

import '../../../../domain/models/expense_entry.dart';
import '../../../../domain/utils/voucher_content_fingerprint.dart';

/// Form-only state for creating/viewing a single van expense.
class ExpenseEditorState extends Equatable {
  final String? editingId;
  final ExpenseEntry? editingExpense;
  final DateTime? editingDate;
  final double editingAmount;
  final String editingCategory;
  final String editingDescription;
  final String? editingReceiptImagePath;
  final Uint8List? editingReceiptImageBytes;
  final bool isEditingNew;

  final bool isEditorLoading;
  final bool isRefreshing;
  final bool isSaving;
  final String? editorError;

  final String? errorMessage;
  final String? successMessage;

  /// Non-blocking toast (refresh result / offline open); does not pop the route.
  final String? infoMessage;

  const ExpenseEditorState({
    this.editingId,
    this.editingExpense,
    this.editingDate,
    this.editingAmount = 0.0,
    this.editingCategory = 'Fuel',
    this.editingDescription = '',
    this.editingReceiptImagePath,
    this.editingReceiptImageBytes,
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
    final exp = editingExpense;
    if (exp == null || exp.isPendingSync) return false;
    final zohoId = exp.zohoExpenseId;
    if (zohoId != null && zohoId.isNotEmpty) return true;
    final id = editingId ?? exp.id;
    if (id.isEmpty || id.startsWith('temp_exp_')) return false;
    return true;
  }

  /// True when form fields differ from the last loaded [editingExpense] snapshot.
  bool get isFormDirty {
    final exp = editingExpense;
    if (exp == null) return false;
    final formFp = VoucherContentFingerprint.expenseForm(
      id: exp.id,
      date: editingDate ?? exp.date,
      amount: editingAmount,
      category: editingCategory,
      description: editingDescription,
    );
    // Compare against single-line projection of the stored expense.
    final snapFp = VoucherContentFingerprint.expenseForm(
      id: exp.id,
      date: exp.date,
      amount: exp.lines.isNotEmpty ? exp.lines.first.amount : exp.amount,
      category: exp.lines.isNotEmpty ? exp.lines.first.category : 'Fuel',
      description:
          exp.lines.isNotEmpty ? exp.lines.first.description : '',
    );
    return formFp != snapFp;
  }

  ExpenseEditorState copyWith({
    String? editingId,
    ExpenseEntry? editingExpense,
    DateTime? editingDate,
    double? editingAmount,
    String? editingCategory,
    String? editingDescription,
    String? editingReceiptImagePath,
    Uint8List? editingReceiptImageBytes,
    bool? isEditingNew,
    bool? isEditorLoading,
    bool? isRefreshing,
    bool? isSaving,
    String? editorError,
    String? errorMessage,
    String? successMessage,
    String? infoMessage,
    bool clearReceiptImage = false,
    bool clearMessages = false,
    bool clearEditingId = false,
    bool clearEditingExpense = false,
    bool clearEditorError = false,
  }) {
    return ExpenseEditorState(
      editingId:
          clearEditingId ? null : (editingId ?? this.editingId),
      editingExpense: (clearEditingId || clearEditingExpense)
          ? null
          : (editingExpense ?? this.editingExpense),
      editingDate: editingDate ?? this.editingDate,
      editingAmount: editingAmount ?? this.editingAmount,
      editingCategory: editingCategory ?? this.editingCategory,
      editingDescription: editingDescription ?? this.editingDescription,
      editingReceiptImagePath: clearReceiptImage
          ? null
          : (editingReceiptImagePath ?? this.editingReceiptImagePath),
      editingReceiptImageBytes: clearReceiptImage
          ? null
          : (editingReceiptImageBytes ?? this.editingReceiptImageBytes),
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
    editingExpense,
    editingDate,
    editingAmount,
    editingCategory,
    editingDescription,
    editingReceiptImagePath,
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
