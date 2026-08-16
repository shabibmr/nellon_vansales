import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/repositories/expense_repository_impl.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/expense_entry.dart';

class _FakeDb extends HiveDatabaseService {
  List<ExpenseEntry> localExpenses = [];
  List<ExpenseEntry> savedRemote = [];
  ExpenseEntry? savedLocal;
  SyncQueueItem? enqueued;
  String? assignedWarehouse;

  @override
  List<ExpenseEntry> getLocalExpenses() => localExpenses;

  @override
  Future<void> saveLocalExpense(ExpenseEntry expense) async {
    savedLocal = expense;
  }

  @override
  Future<void> saveRemoteExpenses(List<ExpenseEntry> remote) async {
    savedRemote = remote;
  }

  @override
  String? get assignedWarehouseId => assignedWarehouse;

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    enqueued = item;
  }
}

class _FakeApi extends ZohoApiClient {
  _FakeApi(HiveDatabaseService db)
    : super(dbService: db);

  bool throwOnDetail = false;
  Map<String, dynamic> detailResponse = {};
  List<Map<String, dynamic>> headersResponse = [];

  @override
  Future<Map<String, dynamic>> fetchExpenseDetail(String expenseId) async {
    if (throwOnDetail) throw Exception('offline');
    return detailResponse;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchExpenseHeaders({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return headersResponse;
  }
}

ExpenseEntry _expense(String id, {bool pending = false}) => ExpenseEntry(
  id: id,
  date: DateTime(2026, 8, 16),
  lines: const [
    ExpenseLineItem(category: 'Fuel', amount: 50, description: ''),
  ],
  isPendingSync: pending,
);

void main() {
  late _FakeDb db;
  late _FakeApi api;
  late ExpenseRepositoryImpl repo;

  setUp(() {
    db = _FakeDb();
    api = _FakeApi(db);
    repo = ExpenseRepositoryImpl(dbService: db, apiClient: api);
  });

  test('getLocalExpenses / saveLocalExpense delegate to dbService', () async {
    db.localExpenses = [_expense('e1')];
    expect(repo.getLocalExpenses(), db.localExpenses);

    final expense = _expense('e2');
    await repo.saveLocalExpense(expense);
    expect(db.savedLocal, expense);
  });

  group('fetchExpenseById', () {
    test('returns local copy without hitting the network when not forcing remote', () async {
      db.localExpenses = [_expense('e1')];
      final result = await repo.fetchExpenseById('e1');
      expect(result?.id, 'e1');
    });

    test('force-remote fetch maps and caches the Zoho response', () async {
      api.detailResponse = {
        'expense_id': 'e1',
        'date': '2026-08-16',
        'line_items': [
          {'account_name': 'Fuel', 'amount': 75, 'description': ''},
        ],
      };
      final result = await repo.fetchExpenseById('e1', forceRemote: true);
      expect(result?.id, 'e1');
      expect(result?.amount, 75);
      expect(db.savedRemote.single.id, 'e1');
    });

    test('offline fallback returns local copy when the remote call fails', () async {
      db.localExpenses = [_expense('e1')];
      api.throwOnDetail = true;
      final result = await repo.fetchExpenseById(
        'e1',
        forceRemote: true,
        allowOfflineFallback: true,
      );
      expect(result?.id, 'e1');
    });

    test('rethrows when the remote call fails and no offline fallback is allowed', () async {
      api.throwOnDetail = true;
      await expectLater(
        repo.fetchExpenseById('e1', forceRemote: true, allowOfflineFallback: false),
        throwsException,
      );
    });
  });

  group('fetchRemoteExpenses', () {
    test('maps headers, stamps the van location, and saves to the local cache', () async {
      db.assignedWarehouse = 'van_1';
      api.headersResponse = [
        {'expense_id': 'e1', 'date': '2026-08-16', 'account_name': 'Fuel', 'total': 40},
      ];
      final result = await repo.fetchRemoteExpenses();
      expect(db.savedRemote, hasLength(1));
      expect(db.savedRemote.single.locationId, 'van_1');
      expect(result, hasLength(1));
    });

    test('keeps pending local drafts the remote set does not include', () async {
      final pendingDraft = _expense('temp_exp_1', pending: true);
      db.localExpenses = [pendingDraft];
      api.headersResponse = [
        {'expense_id': 'e1', 'date': '2026-08-16', 'account_name': 'Fuel', 'total': 40},
      ];
      final result = await repo.fetchRemoteExpenses();
      expect(result.map((e) => e.id), containsAll(['e1', 'temp_exp_1']));
    });
  });

  test('enqueueSyncItem delegates to dbService', () async {
    final item = SyncQueueItem(
      id: 'e1',
      type: 'expense',
      payload: const {},
      timestamp: DateTime(2026, 8, 16),
    );
    await repo.enqueueSyncItem(item);
    expect(db.enqueued, item);
  });
}
