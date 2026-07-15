import '../../../../domain/models/item.dart';
import '../../../../domain/models/sales_invoice.dart';

/// Items from [catalog] that appear on at least one local invoice for [customerId].
List<Item> eligibleReturnItems({
  required List<SalesInvoice> allInvoices,
  required List<Item> catalog,
  required String customerId,
}) {
  final purchasedItemIds = allInvoices
      .where((inv) => inv.customerId == customerId)
      .expand((inv) => inv.items)
      .map((line) => line.item.id)
      .toSet();

  return catalog.where((item) => purchasedItemIds.contains(item.id)).toList();
}

/// Customer invoices containing [itemId], sorted newest-first.
List<SalesInvoice> invoicesContainingItem({
  required List<SalesInvoice> allInvoices,
  required String customerId,
  required String itemId,
}) {
  final matching = allInvoices.where((inv) {
    return inv.customerId == customerId &&
        inv.items.any((line) => line.item.id == itemId);
  }).toList();

  matching.sort((a, b) => b.date.compareTo(a.date));
  return matching;
}