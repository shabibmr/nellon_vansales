import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/repositories/sales_repository_impl.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/unit_conversion.dart';

/// In-memory stand-in for the `item_uom_box` accessors so the resolver can be
/// exercised without opening real Hive boxes.
class _FakeDb extends HiveDatabaseService {
  final Map<String, List<UnitConversion>> uomBox = {};

  @override
  List<UnitConversion> getItemUnitConversions(String itemId) =>
      uomBox[itemId] ?? const [];

  @override
  bool hasItemUnitConversions(String itemId) => uomBox.containsKey(itemId);

  @override
  Future<void> saveItemUnitConversions(
    String itemId,
    List<UnitConversion> conversions,
  ) async {
    uomBox[itemId] = List<UnitConversion>.from(conversions);
  }
}

class _FakeApi extends ZohoApiClient {
  _FakeApi(_FakeDb db) : super(dbService: db);

  final List<String> detailCalls = [];
  bool throwOnFetch = false;

  @override
  Future<Map<String, dynamic>> fetchItemDetail(String itemId) async {
    detailCalls.add(itemId);
    if (throwOnFetch) throw Exception('offline');
    if (itemId == 'plain') {
      // Item with no conversions in Zoho.
      return {'item_id': itemId, 'unit': 'pcs'};
    }
    return {
      'item_id': itemId,
      'unit': 'kg',
      'unit_conversions': [
        {
          'unit_conversion_id': 'uc_$itemId',
          'target_unit_id': 'tu_$itemId',
          'target_unit': '25 Kg Bag',
          'conversion_rate': 25,
          'quantity_decimal_place': 0,
        },
      ],
    };
  }
}

Item _item(String id, {List<UnitConversion> conversions = const []}) => Item(
      id: id,
      name: id,
      sku: id,
      rate: 1,
      stock: 0,
      description: '',
      taxName: '',
      taxPercentage: 0,
      uom: 'kg',
      unitConversions: conversions,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeDb db;
  late _FakeApi api;
  late SalesRepositoryImpl repo;

  setUp(() {
    db = _FakeDb();
    api = _FakeApi(db);
    repo = SalesRepositoryImpl(dbService: db, apiClient: api);
  });

  test('item already carrying conversions is returned without a fetch',
      () async {
    const existing = UnitConversion(
      unitConversionId: 'uc_done',
      targetUnitId: 'tu_done',
      targetUnit: '5 KG',
      conversionRate: 5,
    );
    final resolved =
        await repo.resolveItemUnitConversions(_item('a', conversions: const [existing]));

    expect(api.detailCalls, isEmpty);
    expect(resolved.unitConversions.single.targetUnit, '5 KG');
  });

  test('first selection fetches from Zoho and caches the conversions',
      () async {
    final resolved = await repo.resolveItemUnitConversions(_item('needs1'));

    expect(api.detailCalls, ['needs1']);
    expect(resolved.unitConversions.single.conversionRate, 25.0);
    expect(db.uomBox.containsKey('needs1'), isTrue);
  });

  test('second selection of the same item is served from cache (no fetch)',
      () async {
    await repo.resolveItemUnitConversions(_item('needs1'));
    final again = await repo.resolveItemUnitConversions(_item('needs1'));

    // Only the first call hit the API.
    expect(api.detailCalls, ['needs1']);
    expect(again.unitConversions.single.unitConversionId, 'uc_needs1');
  });

  test('item with no conversions caches an empty entry and never refetches',
      () async {
    final first = await repo.resolveItemUnitConversions(_item('plain'));
    final second = await repo.resolveItemUnitConversions(_item('plain'));

    expect(first.unitConversions, isEmpty);
    expect(second.unitConversions, isEmpty);
    // A present-but-empty entry short-circuits the second fetch.
    expect(api.detailCalls, ['plain']);
    expect(db.uomBox['plain'], isEmpty);
  });

  test('fetch failure falls back to base unit and does NOT cache (retries later)',
      () async {
    api.throwOnFetch = true;
    final resolved = await repo.resolveItemUnitConversions(_item('needs1'));

    expect(resolved.unitConversions, isEmpty);
    expect(db.uomBox.containsKey('needs1'), isFalse);

    // Coming back online, the next selection retries and succeeds.
    api.throwOnFetch = false;
    final retried = await repo.resolveItemUnitConversions(_item('needs1'));
    expect(api.detailCalls, ['needs1', 'needs1']);
    expect(retried.unitConversions.single.conversionRate, 25.0);
  });
}
