import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/ui/core/cubit/list_filter_cubit.dart';

void main() {
  group('ListFilterCubit Tests', () {
    late List<String> initialItems;
    late ListFilterCubit<String> cubit;

    setUp(() {
      initialItems = ['Apple', 'Banana', 'Cherry', 'Date'];
      cubit = ListFilterCubit<String>(
        filterPredicate: (item, query) =>
            item.toLowerCase().contains(query.toLowerCase()),
        initialItems: initialItems,
      );
    });

    tearDown(() {
      cubit.close();
    });

    test('Initial state has empty query and all items as filtered', () {
      expect(cubit.state.query, '');
      expect(cubit.state.allItems, initialItems);
      expect(cubit.state.filteredItems, initialItems);
    });

    test('setQuery filters items correctly (case-insensitive)', () {
      cubit.setQuery('a');
      expect(cubit.state.query, 'a');
      expect(cubit.state.filteredItems, ['Apple', 'Banana', 'Date']);

      cubit.setQuery('ch');
      expect(cubit.state.query, 'ch');
      expect(cubit.state.filteredItems, ['Cherry']);
    });

    test('setQuery with empty string returns all items', () {
      cubit.setQuery('a');
      expect(cubit.state.filteredItems.length, 3);

      cubit.setQuery('');
      expect(cubit.state.filteredItems, initialItems);
    });

    test('setItems updates allItems and re-applies current filter', () {
      cubit.setQuery('a');
      expect(cubit.state.filteredItems, ['Apple', 'Banana', 'Date']);

      final newItems = ['Apricot', 'Blueberry', 'Grape'];
      cubit.setItems(newItems);

      expect(cubit.state.allItems, newItems);
      // 'a' filter applied to newItems -> ['Apricot', 'Grape']
      expect(cubit.state.filteredItems, ['Apricot', 'Grape']);
    });
  });
}
