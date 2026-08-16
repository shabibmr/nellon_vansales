import '../models/item.dart';

/// Abstract contract for the local item/inventory catalog.
abstract class ItemRepository {
  /// Retrieves list of inventory items currently stocked in the van.
  List<Item> getItems();

  /// Resolves an item's multi-UOM conversions on demand.
  ///
  /// Returns the enriched [Item] plus [offlineFallback] = true when a network
  /// fetch was required but failed (no cache). Callers may show a snackbar in
  /// that case; the item is still usable in the base unit.
  Future<({Item item, bool offlineFallback})> resolveItemUnitConversions(
    Item item,
  );
}
