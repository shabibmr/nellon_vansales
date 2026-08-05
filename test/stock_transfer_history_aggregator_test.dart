import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/ui/features/reports/aggregators/stock_transfer_history_aggregator.dart';

void main() {
  final transfer1 = StockTransfer(
    id: 'st_1',
    transferNumber: 'STV-001',
    date: DateTime(2026, 1, 5),
    direction: StockTransferDirection.load,
    fromLocationId: 'loc_warehouse',
    toLocationId: 'loc_van_a',
    lines: const [],
    notes: 'Morning load',
  );

  final transfer2 = StockTransfer(
    id: 'st_2',
    transferNumber: 'STV-002',
    date: DateTime(2026, 1, 10),
    direction: StockTransferDirection.unload,
    fromLocationId: 'loc_van_a',
    toLocationId: 'loc_warehouse',
    lines: const [],
    notes: 'End of day return',
  );

  final transfer3 = StockTransfer(
    id: 'st_3',
    transferNumber: 'STV-003',
    date: DateTime(2026, 1, 15),
    direction: StockTransferDirection.load,
    fromLocationId: 'loc_warehouse',
    toLocationId: 'loc_van_b',
    lines: const [],
  );

  group('StockTransferHistoryAggregator', () {
    test('matches transfers by transfer number or notes case-insensitively', () {
      expect(StockTransferHistoryAggregator.matches(transfer1, 'stv-001'), isTrue);
      expect(StockTransferHistoryAggregator.matches(transfer1, 'morning'), isTrue);
      expect(StockTransferHistoryAggregator.matches(transfer1, 'evening'), isFalse);
      expect(StockTransferHistoryAggregator.matches(transfer1, ''), isTrue);
    });

    test('filters transfers by search query', () {
      final rows = StockTransferHistoryAggregator.aggregate(
        transfers: [transfer1, transfer2, transfer3],
        query: 'return',
      );

      expect(rows.length, equals(1));
      expect(rows.first.transferNumber, equals('STV-002'));
    });

    test('filters transfers by date range', () {
      final rows = StockTransferHistoryAggregator.aggregate(
        transfers: [transfer1, transfer2, transfer3],
        startDate: DateTime(2026, 1, 8),
        endDate: DateTime(2026, 1, 31),
      );

      expect(rows.map((t) => t.transferNumber), equals(['STV-003', 'STV-002']));
    });

    test('sorts by date ascending and descending', () {
      final asc = StockTransferHistoryAggregator.aggregate(
        transfers: [transfer3, transfer1, transfer2],
        sortField: StockTransferHistorySortField.date,
        sortAscending: true,
      );
      expect(
        asc.map((t) => t.transferNumber),
        equals(['STV-001', 'STV-002', 'STV-003']),
      );

      final desc = StockTransferHistoryAggregator.aggregate(
        transfers: [transfer3, transfer1, transfer2],
        sortField: StockTransferHistorySortField.date,
        sortAscending: false,
      );
      expect(
        desc.map((t) => t.transferNumber),
        equals(['STV-003', 'STV-002', 'STV-001']),
      );
    });

    test('sorts by transfer number', () {
      final desc = StockTransferHistoryAggregator.aggregate(
        transfers: [transfer1, transfer2, transfer3],
        sortField: StockTransferHistorySortField.transferNumber,
        sortAscending: false,
      );
      expect(
        desc.map((t) => t.transferNumber),
        equals(['STV-003', 'STV-002', 'STV-001']),
      );
    });

    test('sorts by direction', () {
      final asc = StockTransferHistoryAggregator.aggregate(
        transfers: [transfer2, transfer1, transfer3],
        sortField: StockTransferHistorySortField.direction,
        sortAscending: true,
      );
      // 'load' sorts before 'unload' alphabetically.
      expect(asc.first.direction, equals(StockTransferDirection.load));
      expect(asc.last.direction, equals(StockTransferDirection.unload));
    });

    test('handles empty transfer list', () {
      final rows = StockTransferHistoryAggregator.aggregate(transfers: []);
      expect(rows, isEmpty);
    });
  });
}
