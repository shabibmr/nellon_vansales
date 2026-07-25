/// Thrown when an operation would drive an item's available stock below zero.
class InsufficientStockException implements Exception {
  final String itemId;
  final String itemName;
  final double available;
  final double requested;

  const InsufficientStockException({
    required this.itemId,
    required this.itemName,
    required this.available,
    required this.requested,
  });

  @override
  String toString() =>
      'Cannot fulfill ${_fmt(requested)} unit(s) of "$itemName" — only ${_fmt(available)} available.';

  /// Trims trailing zeros so whole numbers read naturally ("1", not "1.0").
  static String _fmt(double v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toString();
}

/// The single enforced invariant for deducting stock: an item's stock can
/// never be driven below zero. Used by both UI-level validation (before a
/// line item is added or edited) and the persistence layer (before an
/// invoice is committed), so the two can never disagree and stock can never
/// be silently floored to zero.
///
/// Quantities are in the item's base unit (multi-UOM lines are converted to
/// base units before reaching stock math).
double deductStock({
  required String itemId,
  required String itemName,
  required double available,
  required double requested,
}) {
  final remaining = available - requested;
  if (remaining < 0) {
    throw InsufficientStockException(
      itemId: itemId,
      itemName: itemName,
      available: available,
      requested: requested,
    );
  }
  return remaining;
}
