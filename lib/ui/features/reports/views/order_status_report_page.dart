import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../domain/models/sales_order.dart';
import '../../../../domain/repositories/report_repository.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/widgets/document_list_card.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../aggregators/order_status_aggregator.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../widgets/report_bloc_host.dart';

export '../aggregators/order_status_aggregator.dart'
    show OrderStatusFilter, OrderStatusSortField;

/// Full-screen list of sales orders filtered by lifecycle status.
///
/// Fetches every sales order via [ReportRepository] and filters/sorts them using
/// [OrderStatusAggregator] into one of three buckets: open orders not yet delayed,
/// orders already converted to an invoice, or open orders whose shipment date has passed.
class OrderStatusReportPage extends StatelessWidget {
  final OrderStatusFilter filter;
  final String title;

  const OrderStatusReportPage({
    super.key,
    required this.filter,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;
    final DateFormat dateFmt = DateFormat('dd MMM yyyy');

    return ReportBlocHost<SalesOrder>(
      create: (_) => ReportBloc<SalesOrder>(
        fetchRemote: () => context.read<ReportRepository>().fetchSalesOrders(),
        initialSortField: OrderStatusSortField.date,
        initialSortAscending: false,
      ),
      builder: (context, state) {
        final sortField =
            state.sortField as OrderStatusSortField? ?? OrderStatusSortField.date;
        final sortAscending = state.sortAscending;

        final orders = OrderStatusAggregator.aggregate(
          orders: state.rows,
          filter: filter,
          sortField: sortField,
          sortAscending: sortAscending,
        );

        return SortableReportScaffold<SalesOrder, OrderStatusSortField>(
          title: title,
          isLoading: state.isLoading,
          onRefresh: () =>
              context.read<ReportBloc<SalesOrder>>().add(const RefreshReport()),
          rows: orders,
          sortField: sortField,
          sortAscending: sortAscending,
          onSort: (field) =>
              context.read<ReportBloc<SalesOrder>>().add(SetSort(field)),
          emptyIcon: Icons.assignment_outlined,
          emptyTitle: 'No orders found',
          emptyMessage: 'No sales orders match this status right now.',
          columns: const [
            ReportColumn(
              label: 'ORDER / SHIP DATE',
              flex: 5,
              field: OrderStatusSortField.date,
              alignEnd: false,
            ),
            ReportColumn(
              label: 'TOTAL',
              flex: 3,
              field: OrderStatusSortField.total,
            ),
          ],
          exportHeaders: const [
            'Order Number',
            'Customer',
            'Date',
            'Ship Date',
            'Total',
            'Status',
          ],
          exportRow: (order) => [
            order.orderNumber,
            order.customerName,
            dateFmt.format(order.date),
            dateFmt.format(order.shipmentDate),
            order.total.toStringAsFixed(2),
            order.isConverted ? 'Invoiced' : 'Open',
          ],
          itemBuilder: (context, order) {
            return DocumentListCard(
              docNumber: order.orderNumber,
              customerName: order.customerName,
              date: dateFmt.format(order.date),
              subtitle: 'Ship: ${dateFmt.format(order.shipmentDate)}',
              total: '$cs${order.total.toStringAsFixed(2)}',
              itemCount: order.items.length,
              isPendingSync: order.isPendingSync,
              extraBadgeLabel: order.isConverted ? 'Invoiced' : null,
              onTap: () {},
            );
          },
        );
      },
    );
  }
}
