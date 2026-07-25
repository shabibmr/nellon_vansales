import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/ui/features/reports/bloc/shipment_orders_cubit.dart';

Item _item(String id, {String name = 'Item', String sku = 'SKU'}) => Item(
  id: id,
  name: name,
  sku: sku,
  rate: 10,
  stock: 100,
  description: '',
  taxName: 'VAT',
  taxPercentage: 5,
);

SalesOrder _order({
  required String id,
  required DateTime ship,
  SalesOrderStatus status = SalesOrderStatus.open,
  List<OrderLineItem>? items,
  String number = 'SO-1',
}) {
  return SalesOrder(
    id: id,
    orderNumber: number,
    customerId: 'c1',
    customerName: 'Customer',
    date: ship,
    shipmentDate: ship,
    items:
        items ??
        [
          OrderLineItem(
            item: _item('i1', name: 'Milk'),
            quantity: 2,
            rate: 10,
            taxPercentage: 5,
          ),
        ],
    notes: '',
    status: status,
  );
}

void main() {
  group('filterOrdersByShipmentDate', () {
    test('includes only orders within inclusive day range', () {
      final a = _order(id: 'a', ship: DateTime(2026, 7, 10));
      final b = _order(id: 'b', ship: DateTime(2026, 7, 15));
      final c = _order(id: 'c', ship: DateTime(2026, 7, 20));

      final filtered = filterOrdersByShipmentDate(
        [a, b, c],
        startDate: DateTime(2026, 7, 12),
        endDate: DateTime(2026, 7, 18),
      );

      expect(filtered.map((o) => o.id), ['b']);
    });
  });

  group('classifyOrderStatus', () {
    final now = DateTime(2026, 7, 15, 12);

    test('invoiced when converted', () {
      final o = _order(
        id: 'x',
        ship: DateTime(2026, 7, 10),
        status: SalesOrderStatus.invoiced,
      );
      expect(
        classifyOrderStatus(o, now: now),
        ShipmentOrderStatus.invoiced,
      );
    });

    test('delayed when open and ship day before today', () {
      final o = _order(id: 'x', ship: DateTime(2026, 7, 10));
      expect(classifyOrderStatus(o, now: now), ShipmentOrderStatus.delayed);
    });

    test('open when ship day is today or future', () {
      final today = _order(id: 't', ship: DateTime(2026, 7, 15));
      final future = _order(id: 'f', ship: DateTime(2026, 7, 20));
      expect(classifyOrderStatus(today, now: now), ShipmentOrderStatus.open);
      expect(classifyOrderStatus(future, now: now), ShipmentOrderStatus.open);
    });
  });

  group('aggregateItemsFromOrders', () {
    test('sums qty and amount across orders', () {
      final milk = _item('milk', name: 'Milk', sku: 'M1');
      final bread = _item('bread', name: 'Bread', sku: 'B1');
      final o1 = _order(
        id: '1',
        ship: DateTime(2026, 7, 15),
        items: [
          OrderLineItem(
            item: milk,
            quantity: 3,
            rate: 10,
            taxPercentage: 0,
          ),
          OrderLineItem(
            item: bread,
            quantity: 1,
            rate: 20,
            taxPercentage: 0,
          ),
        ],
      );
      final o2 = _order(
        id: '2',
        ship: DateTime(2026, 7, 15),
        items: [
          OrderLineItem(
            item: milk,
            quantity: 2,
            rate: 10,
            taxPercentage: 0,
          ),
        ],
      );

      final rows = aggregateItemsFromOrders([o1, o2]);
      final milkRow = rows.firstWhere((r) => r.itemId == 'milk');
      final breadRow = rows.firstWhere((r) => r.itemId == 'bread');

      expect(milkRow.totalQty, 5);
      expect(milkRow.orderCount, 2);
      expect(breadRow.totalQty, 1);
      expect(breadRow.orderCount, 1);
      expect(demandMapFromSummaries(rows)['milk'], 5);
    });
  });

  group('ShipmentOrdersCubit', () {
    test('toggle select and clear', () {
      final cubit = ShipmentOrdersCubit();
      cubit.toggle('a');
      cubit.toggle('b');
      expect(cubit.state.selectedIds, {'a', 'b'});
      cubit.toggle('a');
      expect(cubit.state.selectedIds, {'b'});
      cubit.clearSelection();
      expect(cubit.state.selectedIds, isEmpty);
      cubit.close();
    });

    test('selectAllOpen skips invoiced', () {
      final cubit = ShipmentOrdersCubit();
      final orders = [
        _order(id: 'open', ship: DateTime(2026, 7, 15)),
        _order(
          id: 'done',
          ship: DateTime(2026, 7, 15),
          status: SalesOrderStatus.invoiced,
        ),
      ];
      cubit.selectAllOpen(orders);
      expect(cubit.state.selectedIds, {'open'});
      expect(cubit.selectedOrders(orders).map((o) => o.id), ['open']);
      cubit.close();
    });
  });
}
