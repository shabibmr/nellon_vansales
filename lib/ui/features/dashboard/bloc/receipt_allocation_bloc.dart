import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/models/open_invoice.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../data/models/receipt_voucher_model.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/services/sync_worker.dart';
import 'receipt_allocation_event.dart';
import 'receipt_allocation_state.dart';

class ReceiptAllocationBloc extends Bloc<ReceiptAllocationEvent, ReceiptAllocationState> {
  final SalesRepository salesRepository;
  final SyncWorker syncWorker;

  ReceiptAllocationBloc({
    required this.salesRepository,
    required this.syncWorker,
  }) : super(const ReceiptAllocationState()) {
    on<ReceiptAllocationStarted>(_onStarted);
    on<OpenInvoicesRefreshRequested>(_onRefreshRequested);
    on<PaymentAmountChanged>(_onAmountChanged);
    on<PaymentModeChanged>(_onPaymentModeChanged);
    on<InvoiceAllocationEdited>(_onAllocationEdited);
    on<ReceiptSubmitted>(_onSubmitted);
  }

  void _onStarted(
    ReceiptAllocationStarted event,
    Emitter<ReceiptAllocationState> emit,
  ) {
    // Show cached open invoices immediately
    final cachedInvoices = salesRepository.getOpenInvoices(customerId: event.customer.id)
      ..sort((a, b) => a.date.compareTo(b.date));

    emit(ReceiptAllocationState(
      customer: event.customer,
      openInvoices: cachedInvoices,
      isLoading: true,
    ));

    // Request remote refresh
    add(OpenInvoicesRefreshRequested());
  }

  Future<void> _onRefreshRequested(
    OpenInvoicesRefreshRequested event,
    Emitter<ReceiptAllocationState> emit,
  ) async {
    final customer = state.customer;
    if (customer == null) return;

    List<OpenInvoice> freshInvoices;
    try {
      // Always pull open invoices live from Zoho — never rely on master sync.
      freshInvoices =
          await salesRepository.fetchRemoteOpenInvoices(customerId: customer.id)
            ..sort((a, b) => a.date.compareTo(b.date));
    } catch (_) {
      // Offline/failure: fall back to last cached snapshot.
      freshInvoices =
          salesRepository.getOpenInvoices(customerId: customer.id)
            ..sort((a, b) => a.date.compareTo(b.date));
    }

    List<PaymentAllocation> newAllocations;
    if (state.hasManualOverride) {
      // Option B: Preserve manual overrides when user has edited
      // We filter the user's manual allocations against the new list of open invoices.
      // - If an invoice is no longer in the fresh list, we drop the allocation.
      // - If it is still open, we keep it but cap it to the new balance.
      newAllocations = <PaymentAllocation>[];
      for (final alloc in state.allocations) {
        final inv = freshInvoices.firstWhere(
          (i) => i.invoiceId == alloc.invoiceId,
          orElse: () => OpenInvoice(
            invoiceId: '',
            invoiceNumber: '',
            customerId: '',
            date: DateTime(1970),
            dueDate: DateTime(1970),
            total: 0.0,
            balance: 0.0,
            status: '',
          ),
        );
        if (inv.invoiceId.isNotEmpty && inv.balance > 0) {
          final cappedAmount = alloc.amountApplied > inv.balance
              ? inv.balance
              : alloc.amountApplied;
          newAllocations.add(
            PaymentAllocation(
              invoiceId: alloc.invoiceId,
              invoiceNumber: alloc.invoiceNumber,
              amountApplied: double.parse(cappedAmount.toStringAsFixed(2)),
            ),
          );
        }
      }
    } else {
      // Re-run FIFO from current amount
      newAllocations = _autoAllocate(freshInvoices, state.paymentAmount);
    }

    emit(state.copyWith(
      openInvoices: freshInvoices,
      allocations: newAllocations,
      isLoading: false,
    ));
  }

  void _onAmountChanged(
    PaymentAmountChanged event,
    Emitter<ReceiptAllocationState> emit,
  ) {
    final amount = double.tryParse(event.rawAmount) ?? 0.0;
    if (amount < 0) return;

    final newAllocations = _autoAllocate(state.openInvoices, amount);

    emit(state.copyWith(
      paymentAmount: amount,
      allocations: newAllocations,
      hasManualOverride: false, // Re-running FIFO clears manual overrides
    ));
  }

  void _onPaymentModeChanged(
    PaymentModeChanged event,
    Emitter<ReceiptAllocationState> emit,
  ) {
    emit(state.copyWith(paymentMode: event.mode));
  }

  void _onAllocationEdited(
    InvoiceAllocationEdited event,
    Emitter<ReceiptAllocationState> emit,
  ) {
    final parsedVal = double.tryParse(event.value) ?? 0.0;
    final cappedVal = parsedVal < 0 ? 0.0 : parsedVal;

    final List<PaymentAllocation> newAllocations = List.from(state.allocations);
    final idx = newAllocations.indexWhere((a) => a.invoiceId == event.invoiceId);

    if (idx >= 0) {
      if (cappedVal <= 0) {
        newAllocations.removeAt(idx);
      } else {
        newAllocations[idx] = PaymentAllocation(
          invoiceId: event.invoiceId,
          invoiceNumber: event.invoiceNumber,
          amountApplied: double.parse(cappedVal.toStringAsFixed(2)),
        );
      }
    } else if (cappedVal > 0) {
      newAllocations.add(
        PaymentAllocation(
          invoiceId: event.invoiceId,
          invoiceNumber: event.invoiceNumber,
          amountApplied: double.parse(cappedVal.toStringAsFixed(2)),
        ),
      );
    }

    emit(state.copyWith(
      allocations: newAllocations,
      hasManualOverride: true, // User edited manually
    ));
  }

  Future<void> _onSubmitted(
    ReceiptSubmitted event,
    Emitter<ReceiptAllocationState> emit,
  ) async {
    if (state.submitting || !state.canSubmit) return;
    emit(state.copyWith(submitting: true, clearSubmitError: true));

    final customer = state.customer;
    if (customer == null) {
      emit(state.copyWith(submitting: false, submitError: 'No customer selected'));
      return;
    }

    try {
      final tempId = 'temp_pay_${DateTime.now().millisecondsSinceEpoch}';
      final voucher = ReceiptVoucher(
        id: tempId,
        paymentNumber: 'PAY-TEMP-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
        customerId: customer.id,
        customerName: customer.name,
        allocations: state.allocations,
        amount: state.paymentAmount,
        paymentMode: state.paymentMode,
        referenceNumber: 'REF-VAN-${DateTime.now().millisecondsSinceEpoch.toString().substring(10)}',
        date: DateTime.now(),
        isPendingSync: true,
      );

      // Save locally
      await salesRepository.saveLocalReceipt(voucher);

      // Enqueue sync item
      final syncItem = SyncQueueItem(
        id: tempId,
        type: 'receipt',
        payload: ReceiptVoucherModel.fromDomain(voucher).toJson(),
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      );
      await salesRepository.enqueueSyncItem(syncItem);

      // Kick sync in background
      syncWorker.syncPendingItems();

      emit(state.copyWith(
        submitting: false,
        submitSuccess: true,
      ));
    } catch (e) {
      emit(state.copyWith(
        submitting: false,
        submitError: e.toString(),
      ));
    }
  }

  List<PaymentAllocation> _autoAllocate(List<OpenInvoice> openInvoices, double amount) {
    if (amount <= 0) return const [];
    final sortedInvoices = List<OpenInvoice>.from(openInvoices)
      ..sort((a, b) => a.date.compareTo(b.date));

    final List<PaymentAllocation> allocations = [];
    double remainingAmount = amount;

    for (final invoice in sortedInvoices) {
      if (remainingAmount <= 0) break;
      final balance = invoice.balance;
      if (balance <= 0) continue;

      final allocated = remainingAmount >= balance ? balance : remainingAmount;
      allocations.add(
        PaymentAllocation(
          invoiceId: invoice.invoiceId,
          invoiceNumber: invoice.invoiceNumber,
          amountApplied: double.parse(allocated.toStringAsFixed(2)),
        ),
      );
      remainingAmount -= allocated;
      remainingAmount = double.parse(remainingAmount.toStringAsFixed(2));
    }
    return allocations;
  }
}
