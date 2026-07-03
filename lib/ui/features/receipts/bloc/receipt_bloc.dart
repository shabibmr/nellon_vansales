import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/open_invoice.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../data/models/receipt_voucher_model.dart';
import '../../../../data/models/sync_queue_item.dart';

// --- Events ---

abstract class ReceiptEvent extends Equatable {
  const ReceiptEvent();
  @override
  List<Object?> get props => [];
}

class LoadReceipts extends ReceiptEvent {}

class SetReceiptDateFilter extends ReceiptEvent {
  final DateTime? startDate;
  final DateTime? endDate;
  const SetReceiptDateFilter({this.startDate, this.endDate});
  @override
  List<Object?> get props => [startDate, endDate];
}

class StartNewReceipt extends ReceiptEvent {}

class StartEditReceipt extends ReceiptEvent {
  final ReceiptVoucher receipt;
  const StartEditReceipt(this.receipt);
  @override
  List<Object?> get props => [receipt];
}

class SetEditingReceiptCustomer extends ReceiptEvent {
  final Customer customer;
  const SetEditingReceiptCustomer(this.customer);
  @override
  List<Object?> get props => [customer];
}

class SetEditingAmount extends ReceiptEvent {
  final double amount;
  const SetEditingAmount(this.amount);
  @override
  List<Object?> get props => [amount];
}

class SetEditingPaymentMode extends ReceiptEvent {
  final String mode;
  const SetEditingPaymentMode(this.mode);
  @override
  List<Object?> get props => [mode];
}

class SetEditingReference extends ReceiptEvent {
  final String reference;
  const SetEditingReference(this.reference);
  @override
  List<Object?> get props => [reference];
}

class SetEditingReceiptDate extends ReceiptEvent {
  final DateTime date;
  const SetEditingReceiptDate(this.date);
  @override
  List<Object?> get props => [date];
}

class UpdateReceiptAllocations extends ReceiptEvent {
  final List<PaymentAllocation> allocations;
  const UpdateReceiptAllocations(this.allocations);
  @override
  List<Object?> get props => [allocations];
}

class SaveReceipt extends ReceiptEvent {}

class ClearReceiptMessages extends ReceiptEvent {}

// --- State ---

class ReceiptState extends Equatable {
  final List<ReceiptVoucher> receipts;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  // Editor fields
  final String? editingId;
  final DateTime? editingDate;
  final Customer? editingCustomer;
  final double editingAmount;
  final String editingPaymentMode;
  final String editingReferenceNumber;
  final List<PaymentAllocation> editingAllocations;
  final bool isEditingNew;

  const ReceiptState({
    this.receipts = const [],
    this.startDate,
    this.endDate,
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
    this.editingId,
    this.editingDate,
    this.editingCustomer,
    this.editingAmount = 0.0,
    this.editingPaymentMode = 'Cash',
    this.editingReferenceNumber = '',
    this.editingAllocations = const [],
    this.isEditingNew = false,
  });

  List<ReceiptVoucher> get filteredReceipts {
    return receipts.where((rec) {
      final day = DateTime(rec.date.year, rec.date.month, rec.date.day);
      if (startDate != null) {
        final s = DateTime(startDate!.year, startDate!.month, startDate!.day);
        if (day.isBefore(s)) return false;
      }
      if (endDate != null) {
        final e = DateTime(endDate!.year, endDate!.month, endDate!.day);
        if (day.isAfter(e)) return false;
      }
      return true;
    }).toList();
  }

  ReceiptState copyWith({
    List<ReceiptVoucher>? receipts,
    DateTime? startDate,
    DateTime? endDate,
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    String? editingId,
    DateTime? editingDate,
    Customer? editingCustomer,
    double? editingAmount,
    String? editingPaymentMode,
    String? editingReferenceNumber,
    List<PaymentAllocation>? editingAllocations,
    bool? isEditingNew,
    bool clearError = false,
    bool clearSuccess = false,
  }) {
    return ReceiptState(
      receipts: receipts ?? this.receipts,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearSuccess
          ? null
          : (successMessage ?? this.successMessage),
      editingId: editingId ?? this.editingId,
      editingDate: editingDate ?? this.editingDate,
      editingCustomer: editingCustomer ?? this.editingCustomer,
      editingAmount: editingAmount ?? this.editingAmount,
      editingPaymentMode: editingPaymentMode ?? this.editingPaymentMode,
      editingReferenceNumber:
          editingReferenceNumber ?? this.editingReferenceNumber,
      editingAllocations: editingAllocations ?? this.editingAllocations,
      isEditingNew: isEditingNew ?? this.isEditingNew,
    );
  }

  @override
  List<Object?> get props => [
    receipts,
    startDate,
    endDate,
    isLoading,
    errorMessage,
    successMessage,
    editingId,
    editingDate,
    editingCustomer,
    editingAmount,
    editingPaymentMode,
    editingReferenceNumber,
    editingAllocations,
    isEditingNew,
  ];
}

// --- Bloc ---

class ReceiptBloc extends Bloc<ReceiptEvent, ReceiptState> {
  final SalesRepository _salesRepository;
  final SyncRepository _syncRepository;

  ReceiptBloc({
    required SalesRepository salesRepository,
    required SyncRepository syncRepository,
  }) : _salesRepository = salesRepository,
       _syncRepository = syncRepository,
       super(const ReceiptState()) {
    on<LoadReceipts>(_onLoadReceipts);
    on<SetReceiptDateFilter>(_onSetDateFilter);
    on<StartNewReceipt>(_onStartNewReceipt);
    on<StartEditReceipt>(_onStartEditReceipt);
    on<SetEditingReceiptCustomer>(_onSetCustomer);
    on<SetEditingAmount>(_onSetAmount);
    on<SetEditingPaymentMode>(_onSetPaymentMode);
    on<SetEditingReference>(_onSetReference);
    on<SetEditingReceiptDate>(_onSetDate);
    on<UpdateReceiptAllocations>(_onUpdateAllocations);
    on<SaveReceipt>(_onSaveReceipt);
    on<ClearReceiptMessages>(_onClearMessages);
  }

  Future<void> _onLoadReceipts(
    LoadReceipts event,
    Emitter<ReceiptState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      final loaded = _salesRepository.getLocalReceipts();
      emit(state.copyWith(receipts: loaded, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  void _onSetDateFilter(
    SetReceiptDateFilter event,
    Emitter<ReceiptState> emit,
  ) {
    emit(state.copyWith(startDate: event.startDate, endDate: event.endDate));
  }

  void _onStartNewReceipt(StartNewReceipt event, Emitter<ReceiptState> emit) {
    emit(
      ReceiptState(
        receipts: state.receipts,
        startDate: state.startDate,
        endDate: state.endDate,
        editingId: 'temp_pay_${DateTime.now().millisecondsSinceEpoch}',
        editingDate: DateTime.now(),
        editingAmount: 0.0,
        editingPaymentMode: 'Cash',
        editingReferenceNumber: '',
        isEditingNew: true,
      ),
    );
  }

  void _onStartEditReceipt(StartEditReceipt event, Emitter<ReceiptState> emit) {
    final rec = event.receipt;
    final customers = _salesRepository.getCustomers();
    final customer = customers.firstWhere(
      (c) => c.id == rec.customerId,
      orElse: () => Customer(
        id: rec.customerId,
        name: rec.customerName,
        companyName: '',
        email: '',
        phone: '',
        address: '',
        outstandingBalance: 0,
        creditLimit: 999999,
        routeId: '',
        sequence: 0,
      ),
    );

    emit(
      ReceiptState(
        receipts: state.receipts,
        startDate: state.startDate,
        endDate: state.endDate,
        editingId: rec.id,
        editingDate: rec.date,
        editingCustomer: customer,
        editingAmount: rec.amount,
        editingPaymentMode: rec.paymentMode,
        editingReferenceNumber: rec.referenceNumber,
        editingAllocations: rec.allocations,
        isEditingNew: false,
      ),
    );
  }

  void _onSetCustomer(
    SetEditingReceiptCustomer event,
    Emitter<ReceiptState> emit,
  ) {
    final allocations = _autoAllocate(event.customer.id, state.editingAmount);
    emit(
      state.copyWith(
        editingCustomer: event.customer,
        editingAllocations: allocations,
      ),
    );
  }

  void _onSetAmount(SetEditingAmount event, Emitter<ReceiptState> emit) {
    final customerId = state.editingCustomer?.id;
    final allocations = customerId != null
        ? _autoAllocate(customerId, event.amount)
        : const <PaymentAllocation>[];
    emit(
      state.copyWith(
        editingAmount: event.amount,
        editingAllocations: allocations,
      ),
    );
  }

  void _onSetPaymentMode(
    SetEditingPaymentMode event,
    Emitter<ReceiptState> emit,
  ) {
    emit(state.copyWith(editingPaymentMode: event.mode));
  }

  void _onSetReference(SetEditingReference event, Emitter<ReceiptState> emit) {
    emit(state.copyWith(editingReferenceNumber: event.reference));
  }

  void _onSetDate(SetEditingReceiptDate event, Emitter<ReceiptState> emit) {
    emit(state.copyWith(editingDate: event.date));
  }

  void _onUpdateAllocations(
    UpdateReceiptAllocations event,
    Emitter<ReceiptState> emit,
  ) {
    emit(state.copyWith(editingAllocations: event.allocations));
  }

  List<PaymentAllocation> _autoAllocate(String customerId, double amount) {
    if (amount <= 0) return const [];
    try {
      final openInvoices = _salesRepository.getOpenInvoices(
        customerId: customerId,
      );
      final sortedInvoices = List<OpenInvoice>.from(openInvoices)
        ..sort((a, b) => a.date.compareTo(b.date));

      final List<PaymentAllocation> allocations = [];
      double remainingAmount = amount;

      for (final invoice in sortedInvoices) {
        if (remainingAmount <= 0) break;
        final balance = invoice.balance;
        if (balance <= 0) continue;

        final allocated = remainingAmount >= balance
            ? balance
            : remainingAmount;
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
    } catch (_) {
      return const [];
    }
  }

  Future<void> _onSaveReceipt(
    SaveReceipt event,
    Emitter<ReceiptState> emit,
  ) async {
    if (state.editingCustomer == null) {
      emit(state.copyWith(errorMessage: 'Please select a customer'));
      return;
    }
    if (state.editingAmount <= 0) {
      emit(state.copyWith(errorMessage: 'Please enter a valid payment amount'));
      return;
    }

    emit(state.copyWith(isLoading: true));
    try {
      final tempId =
          state.editingId ??
          'temp_pay_${DateTime.now().millisecondsSinceEpoch}';
      final ts = DateTime.now().millisecondsSinceEpoch.toString();

      String paymentNum;
      String refNum;
      if (state.isEditingNew) {
        paymentNum = 'PAY-TEMP-${ts.substring(8)}';
        refNum = state.editingReferenceNumber.isNotEmpty
            ? state.editingReferenceNumber
            : 'REF-VAN-${ts.substring(10)}';
      } else {
        final original = state.receipts.firstWhere(
          (r) => r.id == tempId,
          orElse: () => ReceiptVoucher(
            id: tempId,
            paymentNumber: 'PAY-TEMP-${ts.substring(8)}',
            customerId: '',
            customerName: '',
            allocations: const [],
            amount: 0,
            paymentMode: 'Cash',
            referenceNumber: '',
            date: DateTime.now(),
          ),
        );
        paymentNum = original.paymentNumber;
        refNum = state.editingReferenceNumber.isNotEmpty
            ? state.editingReferenceNumber
            : original.referenceNumber;
      }

      final voucher = ReceiptVoucher(
        id: tempId,
        paymentNumber: paymentNum,
        customerId: state.editingCustomer!.id,
        customerName: state.editingCustomer!.name,
        allocations: state.editingAllocations,
        amount: state.editingAmount,
        paymentMode: state.editingPaymentMode,
        referenceNumber: refNum,
        date: state.editingDate ?? DateTime.now(),
        isPendingSync: true,
      );

      await _salesRepository.saveLocalReceipt(voucher);

      final syncItem = SyncQueueItem(
        id: tempId,
        type: 'receipt',
        payload: ReceiptVoucherModel.fromDomain(voucher).toJson(),
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      );
      await _salesRepository.enqueueSyncItem(syncItem);

      _syncRepository.triggerSync();

      final updated = _salesRepository.getLocalReceipts();
      emit(
        state.copyWith(
          receipts: updated,
          isLoading: false,
          successMessage: 'Receipt saved successfully',
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  void _onClearMessages(
    ClearReceiptMessages event,
    Emitter<ReceiptState> emit,
  ) {
    emit(state.copyWith(clearError: true, clearSuccess: true));
  }
}
