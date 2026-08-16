import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../data/services/document_number_service.dart';
import '../../../../data/services/sync_worker.dart';
import '../../../core/utils/error_mapper.dart';
import 'sales_return_dialog_queries.dart';
import 'sales_return_dialog_state.dart';

class SalesReturnDialogCubit extends Cubit<SalesReturnDialogState> {
  final Customer customer;
  final SalesRepository salesRepository;
  final SyncWorker syncWorker;
  final DocumentNumberService documentNumberService;

  SalesReturnDialogCubit({
    required this.customer,
    required this.salesRepository,
    required this.syncWorker,
    required this.documentNumberService,
  }) : super(const SalesReturnDialogState());

  void loadEligibleItems() {
    final invoices = salesRepository.getLocalInvoices();
    final catalog = salesRepository.getItems();
    final eligible = eligibleReturnItems(
      allInvoices: invoices,
      catalog: catalog,
      customerId: customer.id,
    );

    emit(state.copyWith(
      eligibleItems: List<Item>.from(eligible),
      clearSelectedItem: true,
      matchingInvoices: const [],
      quantities: const {},
      clearErrorMessage: true,
      clearSuccess: true,
    ));
  }

  void selectItem(Item item) {
    final invoices = salesRepository.getLocalInvoices();
    final matching = invoicesContainingItem(
      allInvoices: invoices,
      customerId: customer.id,
      itemId: item.id,
    );

    emit(state.copyWith(
      selectedItem: item,
      matchingInvoices: List.from(matching),
      quantities: const {},
      clearErrorMessage: true,
      clearSuccess: true,
    ));
  }

  void setQuantity(String invoiceId, int qty) {
    final clamped = qty < 0 ? 0 : qty;
    final updated = Map<String, int>.from(state.quantities);
    if (clamped == 0) {
      updated.remove(invoiceId);
    } else {
      updated[invoiceId] = clamped;
    }
    emit(state.copyWith(quantities: updated));
  }

  void clearError() {
    if (state.errorMessage != null) {
      emit(state.copyWith(clearErrorMessage: true));
    }
  }

  Future<void> submit() async {
    if (state.submitting) return;

    final selectedItem = state.selectedItem;
    if (selectedItem == null) return;

    final totalQty = state.quantities.values.fold<int>(0, (sum, q) => sum + q);
    if (totalQty <= 0) {
      emit(state.copyWith(
        errorMessage:
            'Please enter return quantity for at least one invoice.',
      ));
      return;
    }

    emit(state.copyWith(submitting: true, clearErrorMessage: true));

    try {
      final returnedLines = <SalesReturnLineItem>[];

      for (final inv in state.matchingInvoices) {
        final qty = state.quantities[inv.id] ?? 0;
        if (qty <= 0) continue;

        final originalLine = inv.items.firstWhere(
          (line) => line.item.id == selectedItem.id,
        );

        returnedLines.add(
          SalesReturnLineItem(
            invoiceLineItem: originalLine,
            returnedQuantity: qty.toDouble(),
            invoiceId: inv.id,
            invoiceNumber: inv.invoiceNumber,
          ),
        );
      }

      final tempId = 'temp_ret_${DateTime.now().millisecondsSinceEpoch}';
      final creditNoteNum = await documentNumberService.nextNumber(
        DocType.creditNote,
      );
      final returnItem = SalesReturn(
        id: tempId,
        creditNoteNumber: creditNoteNum,
        customerId: customer.id,
        customerName: customer.name,
        date: DateTime.now(),
        items: returnedLines,
        reason: 'Damaged packaging',
        isPendingSync: true,
      );

      await salesRepository.submitSalesReturn(returnItem);

      emit(state.copyWith(
        submitting: false,
        success: true,
      ));
    } catch (e) {
      emit(state.copyWith(
        submitting: false,
        errorMessage: userFacingMessage(e),
      ));
    }
  }
}