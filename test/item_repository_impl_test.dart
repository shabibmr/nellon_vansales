import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/repositories/item_repository_impl.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/item.dart';

class _FakeDb extends HiveDatabaseService {
  List<Item> items = [];

  @override
  List<Item> getItems() => items;
}

class _FakeApi extends ZohoApiClient {
  _FakeApi(HiveDatabaseService db)
    : super(dbService: db, mockLatency: Duration.zero);
}

void main() {
  test('getItems delegates to dbService', () {
    final db = _FakeDb();
    final repo = ItemRepositoryImpl(dbService: db, apiClient: _FakeApi(db));

    db.items = [
      const Item(
        id: 'item_1',
        name: 'Milk',
        sku: 'MLK-001',
        rate: 10,
        stock: 50,
        description: '',
        taxName: 'No Tax',
        taxPercentage: 0,
      ),
    ];

    expect(repo.getItems(), db.items);
  });

  // resolveItemUnitConversions' local-first/cache/fetch/offline-fallback
  // behavior is covered exhaustively by test/unit_conversion_resolve_test.dart
  // against this same impl.
}
