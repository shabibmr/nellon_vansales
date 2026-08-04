import 'dart:typed_data';
import 'package:equatable/equatable.dart';

import '../../../../domain/models/expense_entry.dart';

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
  final bool isSaving;
  final String? editorError;

  final String? errorMessage;
  final String? successMessage;

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
    this.isSaving = false,
    this.editorError,
    this.errorMessage,
    this.successMessage,
  });

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
    bool? isSaving,
    String? editorError,
    String? errorMessage,
    String? successMessage,
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
    editingExpense,
    editingDate,
    editingAmount,
    editingCategory,
    editingDescription,
    editingReceiptImagePath,
    isEditingNew,
    isEditorLoading,
    isSaving,
    editorError,
    errorMessage,
    successMessage,
  ];
}
