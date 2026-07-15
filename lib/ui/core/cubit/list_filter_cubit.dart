import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ListFilterState<T> extends Equatable {
  final String query;
  final List<T> allItems;
  final List<T> filteredItems;

  const ListFilterState({
    required this.query,
    required this.allItems,
    required this.filteredItems,
  });

  ListFilterState<T> copyWith({
    String? query,
    List<T>? allItems,
    List<T>? filteredItems,
  }) {
    return ListFilterState<T>(
      query: query ?? this.query,
      allItems: allItems ?? this.allItems,
      filteredItems: filteredItems ?? this.filteredItems,
    );
  }

  @override
  List<Object?> get props => [query, allItems, filteredItems];
}

class ListFilterCubit<T> extends Cubit<ListFilterState<T>> {
  final bool Function(T item, String query) filterPredicate;

  ListFilterCubit({
    required this.filterPredicate,
    List<T> initialItems = const [],
  }) : super(ListFilterState<T>(
          query: '',
          allItems: List.from(initialItems),
          filteredItems: List.from(initialItems),
        ));

  void setItems(List<T> items) {
    final filtered = _filter(items, state.query);
    emit(state.copyWith(
      allItems: List.from(items),
      filteredItems: filtered,
    ));
  }

  void setQuery(String query) {
    final filtered = _filter(state.allItems, query);
    emit(state.copyWith(
      query: query,
      filteredItems: filtered,
    ));
  }

  List<T> _filter(List<T> items, String query) {
    if (query.isEmpty) return List.from(items);
    return items.where((item) => filterPredicate(item, query)).toList();
  }
}
