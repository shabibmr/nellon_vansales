import '../models/stock_transfer.dart';

/// Infers [StockTransferDirection] from the two location ids.
///
/// Zoho Transfer Orders have no `direction` field. Issue-to-Van puts the van
/// in `to`; Stock Unloading puts it in `from`.
///
/// When [vanLocationId] is missing or does not match either end, [stored] is
/// returned (defaulting to [StockTransferDirection.load]).
StockTransferDirection inferStockTransferDirection({
  required String fromLocationId,
  required String toLocationId,
  String? vanLocationId,
  StockTransferDirection? stored,
}) {
  final van = vanLocationId?.trim() ?? '';
  if (van.isNotEmpty) {
    final from = fromLocationId.trim();
    final to = toLocationId.trim();
    if (to == van && from != van) return StockTransferDirection.load;
    if (from == van && to != van) return StockTransferDirection.unload;
  }
  return stored ?? StockTransferDirection.load;
}
