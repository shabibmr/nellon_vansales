import 'package:equatable/equatable.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/sales_invoice.dart';

class SalesReturnDialogState extends Equatable {
  final List<Item> eligibleItems;
  final Item? selectedItem;
  final List<SalesInvoice> matchingInvoices;
  final Map<String, int> quantities;
  final bool submitting;
  final String? errorMessage;
  final bool success;

  const SalesReturnDialogState({
    this.eligibleItems = const [],
    this.selectedItem,
    this.matchingInvoices = const [],
    this.quantities = const {},
    this.submitting = false,
    this.errorMessage,
    this.success = false,
  });

  bool get hasNoPurchaseHistory => eligibleItems.isEmpty;

  bool get canSubmit =>
      selectedItem != null &&
      !submitting &&
      quantities.values.any((q) => q > 0);

  SalesReturnDialogState copyWith({
    List<Item>? eligibleItems,
    Item? selectedItem,
    bool clearSelectedItem = false,
    List<SalesInvoice>? matchingInvoices,
    Map<String, int>? quantities,
    bool? submitting,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? success,
    bool clearSuccess = false,
  }) {
    return SalesReturnDialogState(
      eligibleItems: eligibleItems ?? this.eligibleItems,
      selectedItem:
          clearSelectedItem ? null : (selectedItem ?? this.selectedItem),
      matchingInvoices: matchingInvoices ?? this.matchingInvoices,
      quantities: quantities ?? this.quantities,
      submitting: submitting ?? this.submitting,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      success: clearSuccess ? false : (success ?? this.success),
    );
  }

  @override
  List<Object?> get props => [
        eligibleItems,
        selectedItem,
        matchingInvoices,
        quantities,
        submitting,
        errorMessage,
        success,
      ];
}