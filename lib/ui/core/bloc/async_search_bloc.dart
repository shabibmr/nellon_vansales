import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/models/customer.dart';
import '../../../domain/models/item.dart';
import '../../../domain/repositories/sales_repository.dart';
import 'async_search_event.dart';
import 'async_search_state.dart';

class AsyncSearchBloc extends Bloc<AsyncSearchEvent, AsyncSearchState> {
  final SalesRepository salesRepository;
  Timer? _debounceTimer;

  static const _debounceDuration = Duration(milliseconds: 400);

  AsyncSearchBloc({required this.salesRepository})
      : super(const AsyncSearchState()) {
    on<SearchTypeChanged>(_onSearchTypeChanged);
    on<SearchQueryChanged>(_onSearchQueryChanged);
    on<SearchCleared>(_onSearchCleared);
    on<SearchDebounced>(_onSearchDebounced);
  }

  void _onSearchTypeChanged(
    SearchTypeChanged event,
    Emitter<AsyncSearchState> emit,
  ) {
    _cancelDebounce();
    emit(AsyncSearchState(searchType: event.searchType));
  }

  void _onSearchCleared(
    SearchCleared event,
    Emitter<AsyncSearchState> emit,
  ) {
    _cancelDebounce();
    emit(state.copyWith(
      query: '',
      status: AsyncSearchStatus.idle,
      customerResults: const [],
      itemResults: const [],
    ));
  }

  void _onSearchQueryChanged(
    SearchQueryChanged event,
    Emitter<AsyncSearchState> emit,
  ) {
    _cancelDebounce();
    final trimmed = event.query.trim();

    if (trimmed.isEmpty) {
      emit(state.copyWith(
        query: '',
        status: AsyncSearchStatus.idle,
        customerResults: const [],
        itemResults: const [],
      ));
      return;
    }

    final searchType = state.searchType;
    emit(state.copyWith(
      query: event.query,
      status: AsyncSearchStatus.loading,
      customerResults: const [],
      itemResults: const [],
    ));

    _debounceTimer = Timer(_debounceDuration, () {
      add(SearchDebounced(query: trimmed, searchType: searchType));
    });
  }

  void _onSearchDebounced(
    SearchDebounced event,
    Emitter<AsyncSearchState> emit,
  ) {
    if (event.searchType == SearchType.customers) {
      final results = _filterCustomers(event.query);
      if (results.isEmpty) {
        emit(state.copyWith(
          query: event.query,
          status: AsyncSearchStatus.empty,
          customerResults: const [],
          itemResults: const [],
        ));
      } else {
        emit(state.copyWith(
          query: event.query,
          status: AsyncSearchStatus.results,
          customerResults: List<Customer>.from(results),
          itemResults: const [],
        ));
      }
    } else {
      final results = _filterItems(event.query);
      if (results.isEmpty) {
        emit(state.copyWith(
          query: event.query,
          status: AsyncSearchStatus.empty,
          customerResults: const [],
          itemResults: const [],
        ));
      } else {
        emit(state.copyWith(
          query: event.query,
          status: AsyncSearchStatus.results,
          customerResults: const [],
          itemResults: List<Item>.from(results),
        ));
      }
    }
  }

  List<Customer> _filterCustomers(String query) {
    final lowercaseQuery = query.toLowerCase();
    return salesRepository.getCustomers().where((cust) {
      return cust.name.toLowerCase().contains(lowercaseQuery) ||
          cust.companyName.toLowerCase().contains(lowercaseQuery) ||
          cust.phone.contains(query);
    }).toList();
  }

  List<Item> _filterItems(String query) {
    final lowercaseQuery = query.toLowerCase();
    return salesRepository.getItems().where((item) {
      return item.name.toLowerCase().contains(lowercaseQuery) ||
          item.sku.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }

  void _cancelDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  @override
  Future<void> close() {
    _cancelDebounce();
    return super.close();
  }
}