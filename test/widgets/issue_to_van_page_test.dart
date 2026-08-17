import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/warehouse.dart';
import 'package:van_sales/ui/core/utils/date_filter.dart';
import 'package:van_sales/ui/features/stock_transfer/bloc/stock_transfer_bloc.dart';
import 'package:van_sales/ui/features/stock_transfer/views/issue_to_van_page.dart';

class _FakeStockTransferBloc extends Fake implements StockTransferBloc {
  _FakeStockTransferBloc(this._state);

  final StockTransferState _state;
  final _controller = StreamController<StockTransferState>.broadcast();

  @override
  StockTransferState get state => _state;

  @override
  Stream<StockTransferState> get stream => _controller.stream;

  @override
  void add(StockTransferEvent event) {}

  @override
  Future<void> close() async {
    await _controller.close();
  }
}

void main() {
  const item = Item(
    id: 'item_1',
    name: 'Nellon Ghee',
    sku: 'SKU1',
    rate: 10,
    stock: 8,
    description: '',
    taxName: 'No Tax',
    taxPercentage: 0,
  );

  testWidgets(
    'Issue to Van shows a from/to/date header and a line tile per row',
    (tester) async {
      final bloc = _FakeStockTransferBloc(
        const StockTransferState(
          defaultWarehouse: Warehouse(
            id: 'wh',
            name: 'Main Store',
            address: '',
          ),
          currentLocation: Warehouse(
            id: 'van',
            name: 'SHINAD',
            address: '',
          ),
          rows: [
            StockTransferRow(item: item, currentStock: 8, invoiceQty: 3),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<StockTransferBloc>.value(
            value: bloc,
            child: const IssueToVanPage(),
          ),
        ),
      );

      expect(find.text('Issue to Van'), findsOneWidget);
      expect(find.text('Main Store'), findsOneWidget);
      expect(find.text('SHINAD'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
      expect(
        find.text(DateFormat('dd MMM yyyy').format(todayDate())),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.event_outlined), findsOneWidget);

      // Line tile: item identity + current stock + resulting grand total,
      // no rate/tax/currency (transfer lines carry no money).
      expect(find.text('Nellon Ghee'), findsOneWidget);
      expect(find.textContaining('Current: 8'), findsOneWidget);
      expect(find.textContaining('Grand:'), findsOneWidget);

      // Notes field is always visible now (was previously hidden).
      expect(find.widgetWithText(TextField, 'Notes'), findsOneWidget);

      // Add Item is available while creating (not read-only).
      expect(find.widgetWithText(OutlinedButton, 'Add Item'), findsOneWidget);

      await bloc.close();
    },
  );
}
