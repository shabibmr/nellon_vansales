import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/repositories/cash_closing_repository_impl.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/domain/models/cash_closing.dart';

class _FakeDb extends HiveDatabaseService {
  CashClosing? saved;
  bool pending = false;
  SyncQueueItem? enqueued;

  @override
  CashClosing? getLocalCashClosing() => saved;

  @override
  Future<void> saveLocalCashClosing(CashClosing closing) async {
    saved = closing;
  }

  @override
  bool hasPendingCashClosingForToday() => pending;

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    enqueued = item;
  }
}

void main() {
  late _FakeDb db;
  late CashClosingRepositoryImpl repo;

  setUp(() {
    db = _FakeDb();
    repo = CashClosingRepositoryImpl(dbService: db);
  });

  test('getLocalCashClosing delegates to dbService', () {
    expect(repo.getLocalCashClosing(), isNull);
    final closing = CashClosing(
      id: 'cc0',
      date: DateTime(2026, 8, 16),
      openingBalance: 0,
      totalSalesInvoices: 0,
      totalReceiptsCollected: 0,
      totalExpenses: 0,
      closingBalance: 500,
      notes: '',
    );
    db.saved = closing;
    expect(repo.getLocalCashClosing(), closing);
  });

  test('saveLocalCashClosing delegates to dbService', () async {
    final closing = CashClosing(
      id: 'cc1',
      date: DateTime(2026, 8, 16),
      openingBalance: 1000,
      totalSalesInvoices: 500,
      totalReceiptsCollected: 300,
      totalExpenses: 50,
      closingBalance: 1250,
      notes: '',
    );
    await repo.saveLocalCashClosing(closing);
    expect(db.saved, closing);
  });

  test('hasPendingCashClosingForToday delegates to dbService', () {
    expect(repo.hasPendingCashClosingForToday(), isFalse);
    db.pending = true;
    expect(repo.hasPendingCashClosingForToday(), isTrue);
  });

  test('enqueueSyncItem delegates to dbService', () async {
    final item = SyncQueueItem(
      id: 'cc1',
      type: 'expense',
      payload: const <String, dynamic>{},
      timestamp: DateTime(2026, 8, 16),
    );
    await repo.enqueueSyncItem(item);
    expect(db.enqueued, item);
  });
}
