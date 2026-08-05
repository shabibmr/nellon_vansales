import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/ui/core/widgets/sortable_report_scaffold.dart';

enum _SortField { name }

void main() {
  testWidgets('SortableReportScaffold shows loading then empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SortableReportScaffold<String, _SortField>(
          title: 'Item Sales',
          isLoading: true,
          onRefresh: () {},
          rows: const [],
          columns: const [
            ReportColumn(label: 'Item', flex: 2, field: _SortField.name),
          ],
          sortField: _SortField.name,
          sortAscending: true,
          onSort: (_) {},
          itemBuilder: (context, row) => Text(row),
          emptyTitle: 'No rows',
          emptyMessage: 'No sales',
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: SortableReportScaffold<String, _SortField>(
          title: 'Item Sales',
          isLoading: false,
          onRefresh: () {},
          rows: const [],
          columns: const [
            ReportColumn(label: 'Item', flex: 2, field: _SortField.name),
          ],
          sortField: _SortField.name,
          sortAscending: true,
          onSort: (_) {},
          itemBuilder: (context, row) => Text(row),
          emptyTitle: 'No rows',
          emptyMessage: 'No sales in range',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('No sales in range'), findsOneWidget);
  });
}
