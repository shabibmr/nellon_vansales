/// Thrown when an operation would drive an item's available stock below zero.
class InsufficientStockException implements Exception {
  final String itemId;
  final String itemName;
  final int available;
  final int requested;

  const InsufficientStockException({
    required this.itemId,
    required this.itemName,
    required this.available,
    required this.requested,
  });

  @override
  String toString() =>
      'Cannot fulfill $requested unit(s) of "$itemName" — only $available available.';
}

/// The single enforced invariant for deducting stock: an item's stock can
/// never be driven below zero. Used by both UI-level validation (before a
/// line item is added or edited) and the persistence layer (before an
/// invoice is committed), so the two can never disagree and stock can never
/// be silently floored to zero.
int deductStock({
  required String itemId,
  required String itemName,
  required int available,
  required int requested,
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
