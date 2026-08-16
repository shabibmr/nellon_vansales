import '../../domain/models/item.dart';
import '../../domain/models/unit_conversion.dart';
import '../../domain/repositories/item_repository.dart';
import '../models/unit_conversion_model.dart';
import '../services/app_logger.dart';
import '../services/hive_database_service.dart';
import '../services/zoho_api_client.dart';

/// Concrete implementation of [ItemRepository] backed by a local Hive
/// database cache and the Zoho Books API.
class ItemRepositoryImpl implements ItemRepository {
  final HiveDatabaseService _dbService;
  final ZohoApiClient _apiClient;

  ItemRepositoryImpl({required this._dbService, required this._apiClient});

  @override
  List<Item> getItems() => _dbService.getItems();

  @override
  Future<({Item item, bool offlineFallback})> resolveItemUnitConversions(
    Item item,
  ) async {
    // Already enriched (e.g. carried on an existing line item) — nothing to do.
    if (item.unitConversions.isNotEmpty) {
      return (item: item, offlineFallback: false);
    }

    // Previously resolved: serve from the dedicated item-UOM box. A cached but
    // empty entry means "checked, none exist" — still short-circuits the fetch.
    if (_dbService.hasItemUnitConversions(item.id)) {
      final cached = _dbService.getItemUnitConversions(item.id);
      final resolved =
          cached.isEmpty ? item : item.copyWith(unitConversions: cached);
      return (item: resolved, offlineFallback: false);
    }

    // First selection while (hopefully) online — the /items list endpoint never
    // returns unit_conversions, so fetch the item detail once and cache it.
    try {
      final detail = await _apiClient.fetchItemDetail(item.id);
      final conversions =
          (detail['unit_conversions'] as List<dynamic>? ?? const [])
              .map(
                (c) => UnitConversionModel.fromJson(
                  Map<String, dynamic>.from(c as Map),
                ) as UnitConversion,
              )
              .toList();
      // Persist even when empty so we don't re-hit Zoho for this item.
      await _dbService.saveItemUnitConversions(item.id, conversions);
      final resolved = conversions.isEmpty
          ? item
          : item.copyWith(unitConversions: conversions);
      return (item: resolved, offlineFallback: false);
    } catch (e) {
      // Offline / rate-limited / any failure: fall back to base-unit-only and
      // do NOT cache, so a later online selection retries the fetch.
      AppLogger.error(
        'ItemRepository',
        'resolveItemUnitConversions(${item.id}) error: $e',
      );
      return (item: item, offlineFallback: true);
    }
  }
}
