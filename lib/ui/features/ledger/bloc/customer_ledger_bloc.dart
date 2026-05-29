import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/customer_ledger.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../data/services/zoho_api_client.dart';

// --- Events ---

abstract class CustomerLedgerEvent extends Equatable {
  const CustomerLedgerEvent();
  @override
  List<Object?> get props => [];
}

class SetLedgerCustomer extends CustomerLedgerEvent {
  final Customer customer;
  const SetLedgerCustomer(this.customer);
  @override
  List<Object?> get props => [customer];
}

class SetLedgerStartDate extends CustomerLedgerEvent {
  final DateTime date;
  const SetLedgerStartDate(this.date);
  @override
  List<Object?> get props => [date];
}

class SetLedgerEndDate extends CustomerLedgerEvent {
  final DateTime date;
  const SetLedgerEndDate(this.date);
  @override
  List<Object?> get props => [date];
}

class FetchLedger extends CustomerLedgerEvent {}

class ClearLedger extends CustomerLedgerEvent {}

// --- State ---

class CustomerLedgerState extends Equatable {
  final Customer? selectedCustomer;
  final DateTime startDate;
  final DateTime endDate;
  final CustomerLedger? ledger;
  final bool isLoading;
  final String? errorMessage;

  CustomerLedgerState({
    this.selectedCustomer,
    DateTime? startDate,
    DateTime? endDate,
    this.ledger,
    this.isLoading = false,
    this.errorMessage,
  })  : startDate = startDate ?? _currentFinancialYearStart(),
        endDate = endDate ?? DateTime.now();

  /// Returns April 1 of the current financial year (India FY starts in April).
  static DateTime _currentFinancialYearStart() {
    final now = DateTime.now();
    final year = now.month >= 4 ? now.year : now.year - 1;
    return DateTime(year, 4, 1);
  }

  bool get canFetch => selectedCustomer != null && !isLoading;

  CustomerLedgerState copyWith({
    Customer? selectedCustomer,
    DateTime? startDate,
    DateTime? endDate,
    CustomerLedger? ledger,
    bool? isLoading,
    String? errorMessage,
    bool clearLedger = false,
    bool clearError = false,
  }) {
    return CustomerLedgerState(
      selectedCustomer: selectedCustomer ?? this.selectedCustomer,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      ledger: clearLedger ? null : (ledger ?? this.ledger),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        selectedCustomer,
        startDate,
        endDate,
        ledger,
        isLoading,
        errorMessage,
      ];
}

// --- Bloc ---

class CustomerLedgerBloc
    extends Bloc<CustomerLedgerEvent, CustomerLedgerState> {
  final SalesRepository _salesRepository;
  final ZohoApiClient _apiClient;

  CustomerLedgerBloc({
    required SalesRepository salesRepository,
    required ZohoApiClient apiClient,
  })  : _salesRepository = salesRepository,
        _apiClient = apiClient,
        super(CustomerLedgerState()) {
    on<SetLedgerCustomer>(_onSetCustomer);
    on<SetLedgerStartDate>(_onSetStartDate);
    on<SetLedgerEndDate>(_onSetEndDate);
    on<FetchLedger>(_onFetchLedger);
    on<ClearLedger>(_onClearLedger);
  }

  // expose local customer list for the selector UI
  List<Customer> get customers => _salesRepository.getCustomers()
    ..sort((a, b) => a.name.compareTo(b.name));

  void _onSetCustomer(SetLedgerCustomer event, Emitter<CustomerLedgerState> emit) {
    emit(state.copyWith(
      selectedCustomer: event.customer,
      clearLedger: true,
      clearError: true,
    ));
  }

  void _onSetStartDate(SetLedgerStartDate event, Emitter<CustomerLedgerState> emit) {
    emit(state.copyWith(startDate: event.date, clearLedger: true));
  }

  void _onSetEndDate(SetLedgerEndDate event, Emitter<CustomerLedgerState> emit) {
    emit(state.copyWith(endDate: event.date, clearLedger: true));
  }

  Future<void> _onFetchLedger(FetchLedger event, Emitter<CustomerLedgerState> emit) async {
    if (state.selectedCustomer == null) return;

    emit(state.copyWith(isLoading: true, clearError: true, clearLedger: true));
    try {
      final raw = await _apiClient.fetchCustomerStatement(
        state.selectedCustomer!.id,
        startDate: state.startDate,
        endDate: state.endDate,
      );

      // Inject the real customer name from local cache when Zoho returns a generic/mock name
      final rawWithName = Map<String, dynamic>.from(raw);
      if ((rawWithName['contact_name'] as String? ?? '').isEmpty ||
          rawWithName['contact_name'] == 'Demo Customer') {
        rawWithName['contact_name'] = state.selectedCustomer!.name;
      }

      final ledger = CustomerLedger.fromJson(rawWithName, state.selectedCustomer!.id);
      emit(state.copyWith(ledger: ledger, isLoading: false));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      ));
    }
  }

  void _onClearLedger(ClearLedger event, Emitter<CustomerLedgerState> emit) {
    emit(state.copyWith(clearLedger: true, clearError: true));
  }
}
