import 'package:equatable/equatable.dart';
import '../../../domain/models/customer.dart';
import '../../../domain/models/item.dart';

/// Search category for the global async search widget.
enum SearchType {
  customers,
  items,
}

/// Lifecycle of an in-memory search query.
enum AsyncSearchStatus {
  idle,
  loading,
  results,
  empty,
}

class AsyncSearchState extends Equatable {
  final SearchType searchType;
  final String query;
  final AsyncSearchStatus status;
  final List<Customer> customerResults;
  final List<Item> itemResults;

  const AsyncSearchState({
    this.searchType = SearchType.customers,
    this.query = '',
    this.status = AsyncSearchStatus.idle,
    this.customerResults = const [],
    this.itemResults = const [],
  });

  bool get hasSearched =>
      status == AsyncSearchStatus.loading ||
      status == AsyncSearchStatus.results ||
      status == AsyncSearchStatus.empty;

  AsyncSearchState copyWith({
    SearchType? searchType,
    String? query,
    AsyncSearchStatus? status,
    List<Customer>? customerResults,
    List<Item>? itemResults,
  }) {
    return AsyncSearchState(
      searchType: searchType ?? this.searchType,
      query: query ?? this.query,
      status: status ?? this.status,
      customerResults: customerResults ?? this.customerResults,
      itemResults: itemResults ?? this.itemResults,
    );
  }

  @override
  List<Object?> get props => [
        searchType,
        query,
        status,
        customerResults,
        itemResults,
      ];
}