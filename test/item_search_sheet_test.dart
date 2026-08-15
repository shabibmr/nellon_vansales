import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/organization.dart';
import 'package:van_sales/ui/core/cubit/list_filter_cubit.dart';
import 'package:van_sales/ui/core/cubit/organization_cubit.dart';
import 'package:van_sales/ui/core/widgets/item_search_sheet.dart';

Item _item(String id, String name, double stock) => Item(
  id: id,
  name: name,
  sku: 'SKU-$id',
  rate: 10,
  stock: stock,
  description: '',
  taxName: 'No Tax',
  taxPercentage: 0,
);

class _FakeOrgCubit extends Cubit<Organization?> implements OrganizationCubit {
  _FakeOrgCubit() : super(null);

  @override
  String get currencySymbol => 'AED';

  @override
  String get companyName => 'Test Co';

  @override
  String get currencyCode => 'AED';

  @override
  void refresh() {}
}

void main() {
  final inStock = _item('1', 'Ghee', 8);
  final zeroStock = _item('2', 'Pappadam', 0);
  final negativeStock = _item('3', 'Soda', -2);

  group('visibleSearchItems', () {
    test('keeps only stock > 0 unless showAll', () {
      final items = [inStock, zeroStock, negativeStock];
      expect(
        visibleSearchItems(items, showAll: false).map((i) => i.id),
        ['1'],
      );
      expect(
        visibleSearchItems(items, showAll: true).map((i) => i.id),
        ['1', '2', '3'],
      );
    });
  });

  group('ItemSearchSheet', () {
    Future<void> pumpSheet(WidgetTester tester, List<Item> items) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<OrganizationCubit>.value(value: _FakeOrgCubit()),
              BlocProvider(
                create: (_) => ListFilterCubit<Item>(
                  initialItems: items,
                  filterPredicate: (item, query) {
                    final q = query.toLowerCase();
                    return item.name.toLowerCase().contains(q) ||
                        item.sku.toLowerCase().contains(q);
                  },
                ),
              ),
            ],
            child: Scaffold(
              body: ItemSearchSheet(
                items: items,
                title: 'Search items',
                emptyMessage: 'No items available',
                onSelected: (item, context) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('defaults to in-stock items and Show all reveals the rest', (
      tester,
    ) async {
      await pumpSheet(tester, [inStock, zeroStock, negativeStock]);

      expect(find.text('Show all'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(find.text('Ghee'), findsOneWidget);
      expect(find.text('Pappadam'), findsNothing);
      expect(find.text('Soda'), findsNothing);

      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();

      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      expect(find.text('Ghee'), findsOneWidget);
      expect(find.text('Pappadam'), findsOneWidget);
      expect(find.text('Soda'), findsOneWidget);
    });
  });
}
