import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/models/sales_order.dart';
import '../../../core/utils/date_filter.dart';

/// Lifecycle status for display on shipment-order tiles.
enum ShipmentOrderStatus { open, delayed, invoiced }

/// Aggregated demand row for the Items tab.
class ShipmentItemSummary extends Equatable {
  final String itemId;
  final String itemName;
  final String sku;
  final double totalQty;
  final double totalAmount;
  final int orderCount;

  const ShipmentItemSummary({
    required this.itemId,
    required this.itemName,
    required this.sku,
    required this.totalQty,
    required this.totalAmount,
    required this.orderCount,
  });

  @override
  List<Object?> get props => [
    itemId,
    itemName,
    sku,
    totalQty,
    totalAmount,
    orderCount,
  ];
}

/// Filters [orders] to those whose [SalesOrder.shipmentDate] falls in
/// the inclusive [startDate]/[endDate] day range.
List<SalesOrder> filterOrdersByShipmentDate(
  List<SalesOrder> orders, {
  DateTime? startDate,
  DateTime? endDate,
}) {
  return filterByDateRange(
    orders,
    (order) => order.shipmentDate,
    startDate: startDate,
    endDate: endDate,
  );
}

/// Classifies an order for status pills (invoiced / delayed / open).
ShipmentOrderStatus classifyOrderStatus(
  SalesOrder order, {
  DateTime? now,
}) {
  if (order.isConverted) return ShipmentOrderStatus.invoiced;
  final reference = now ?? DateTime.now();
  final shipDay = DateTime(
    order.shipmentDate.year,
    order.shipmentDate.month,
    order.shipmentDate.day,
  );
  final todayDay = DateTime(reference.year, reference.month, reference.day);
  if (shipDay.isBefore(todayDay)) return ShipmentOrderStatus.delayed;
  return ShipmentOrderStatus.open;
}

String shipmentOrderStatusLabel(ShipmentOrderStatus status) {
  return switch (status) {
    ShipmentOrderStatus.open => 'Open',
    ShipmentOrderStatus.delayed => 'Delayed',
    ShipmentOrderStatus.invoiced => 'Invoiced',
  };
}

/// Aggregates line items across [orders] by item id.
List<ShipmentItemSummary> aggregateItemsFromOrders(List<SalesOrder> orders) {
  final map = <String, _MutableItemAgg>{};
  for (final order in orders) {
    final seenInOrder = <String>{};
    for (final line in order.items) {
      final id = line.item.id;
      final agg = map.putIfAbsent(
        id,
        () => _MutableItemAgg(
          itemId: id,
          itemName: line.item.name,
          sku: line.item.sku,
        ),
      );
      // Base-unit quantities — order lines may be in alternate units, and the
      // demand map feeds Issue-to-Van which works in base units.
      agg.totalQty += line.quantityInBase;
      agg.totalAmount += line.total;
      if (seenInOrder.add(id)) {
        agg.orderCount += 1;
      }
    }
  }
  final rows = map.values
      .map(
        (a) => ShipmentItemSummary(
          itemId: a.itemId,
          itemName: a.itemName,
          sku: a.sku,
          totalQty: a.totalQty,
          totalAmount: a.totalAmount,
          orderCount: a.orderCount,
        ),
      )
      .toList()
    ..sort((a, b) => a.itemName.compareTo(b.itemName));
  return rows;
}

/// Demand map suitable for Issue-to-Van prefill (`itemId → qty`).
Map<String, double> demandMapFromSummaries(List<ShipmentItemSummary> rows) {
  return {for (final r in rows) r.itemId: r.totalQty};
}

class _MutableItemAgg {
  final String itemId;
  final String itemName;
  final String sku;
  double totalQty = 0;
  double totalAmount = 0;
  int orderCount = 0;

  _MutableItemAgg({
    required this.itemId,
    required this.itemName,
    required this.sku,
  });
}

/// Page-scoped selection state for the shipment orders report.
class ShipmentOrdersSelectionState extends Equatable {
  final Set<String> selectedIds;

  const ShipmentOrdersSelectionState({this.selectedIds = const {}});

  int get selectedCount => selectedIds.length;

  bool isSelected(String orderId) => selectedIds.contains(orderId);

  ShipmentOrdersSelectionState copyWith({Set<String>? selectedIds}) {
    return ShipmentOrdersSelectionState(
      selectedIds: selectedIds ?? this.selectedIds,
    );
  }

  @override
  List<Object?> get props => [selectedIds];
}

class ShipmentOrdersCubit extends Cubit<ShipmentOrdersSelectionState> {
  ShipmentOrdersCubit() : super(const ShipmentOrdersSelectionState());

  void toggle(String orderId) {
    final next = Set<String>.from(state.selectedIds);
    if (!next.add(orderId)) {
      next.remove(orderId);
    }
    emit(state.copyWith(selectedIds: next));
  }

  void selectAllOpen(List<SalesOrder> orders) {
    final openIds = orders
        .where((o) => !o.isConverted)
        .map((o) => o.id)
        .toSet();
    emit(state.copyWith(selectedIds: openIds));
  }

  void clearSelection() {
    emit(const ShipmentOrdersSelectionState());
  }

  /// Drops ids that are no longer present or no longer open.
  void pruneToOpen(List<SalesOrder> orders) {
    final openIds = orders
        .where((o) => !o.isConverted)
        .map((o) => o.id)
        .toSet();
    final next = state.selectedIds.intersection(openIds);
    if (next.length != state.selectedIds.length) {
      emit(state.copyWith(selectedIds: next));
    }
  }

  List<SalesOrder> selectedOrders(List<SalesOrder> filtered) {
    return filtered
        .where((o) => state.selectedIds.contains(o.id) && !o.isConverted)
        .toList();
  }
}
