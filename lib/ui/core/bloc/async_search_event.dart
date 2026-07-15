import 'package:equatable/equatable.dart';
import 'async_search_state.dart';

abstract class AsyncSearchEvent extends Equatable {
  const AsyncSearchEvent();

  @override
  List<Object?> get props => [];
}

class SearchTypeChanged extends AsyncSearchEvent {
  final SearchType searchType;

  const SearchTypeChanged(this.searchType);

  @override
  List<Object?> get props => [searchType];
}

class SearchQueryChanged extends AsyncSearchEvent {
  final String query;

  const SearchQueryChanged(this.query);

  @override
  List<Object?> get props => [query];
}

class SearchCleared extends AsyncSearchEvent {
  const SearchCleared();
}

/// Internal event fired after the debounce timer elapses.
class SearchDebounced extends AsyncSearchEvent {
  final String query;
  final SearchType searchType;

  const SearchDebounced({
    required this.query,
    required this.searchType,
  });

  @override
  List<Object?> get props => [query, searchType];
}