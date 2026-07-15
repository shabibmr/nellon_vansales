import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../data/models/sales_order_model.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/sales_order.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/document_list_card.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../bloc/report_state.dart';

enum _SortField { date, total }

/// Which bucket of sales orders an [OrderStatusReportPage] shows.
///
/// [readyOrPending] backs both the "Orders Ready" and "Pending Orders" tiles:
/// `SalesOrder` has no fulfillment-progress field beyond `status`/
/// `shipmentDate`, so there is nothing in the data model today that
/// distinguishes "ready to ship" from "not yet prepared" — both tiles
/// intentionally show the same open-and-not-delayed bucket.
enum OrderStatusFilter { readyOrPending, invoiced, delayed }

/// Full-screen list of sales orders filtered by lifecycle status.
///
/// Fetches every sales order live from Zoho Books and filters to one of
/// three buckets: open orders not yet delayed, orders already converted to
/// an invoice, or open orders whose shipment date has passed.
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
    return BlocProvider<ReportBloc<SalesOrder>>(
      create: (_) => ReportBloc<SalesOrder>(
        getLocal: () => sl<HiveDatabaseService>().getLocalOrders(),
        fetchRemote: () async {
          final raw = await sl<ZohoApiClient>().fetchSalesOrders();
          return raw.map((json) => SalesOrderModel.fromJson(json)).toList();
        },
        initialSortField: _SortField.date,
        initialSortAscending: false,
      ),
      child: _OrderStatusReportView(
        filter: filter,
        title: title,
      ),
    );
  }
}

class _OrderStatusReportView extends StatelessWidget {
  final OrderStatusFilter filter;
  final String title;

  const _OrderStatusReportView({
    required this.filter,
    required this.title,
  });

  bool _matches(SalesOrder order) {
    final today = DateTime.now();
    final shipDay = DateTime(
      order.shipmentDate.year,
      order.shipmentDate.month,
      order.shipmentDate.day,
    );
    final todayDay = DateTime(today.year, today.month, today.day);

    switch (filter) {
      case OrderStatusFilter.invoiced:
        return order.isConverted;
      case OrderStatusFilter.delayed:
        return !order.isConverted && shipDay.isBefore(todayDay);
      case OrderStatusFilter.readyOrPending:
        return !order.isConverted && !shipDay.isBefore(todayDay);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;
    final DateFormat dateFmt = DateFormat('dd MMM yyyy');

    return BlocListener<ReportBloc<SalesOrder>, ReportState<SalesOrder>>(
      listenWhen: (prev, curr) => curr.error != null && prev.error != curr.error,
      listener: (context, state) {
        showErrorSnackBar(context, 'Could not load report from Zoho: ${state.error}');
      },
      child: BlocBuilder<ReportBloc<SalesOrder>, ReportState<SalesOrder>>(
        builder: (context, state) {
          final sortField = state.sortField as _SortField? ?? _SortField.date;
          final sortAscending = state.sortAscending;

          final orders = state.rows.where(_matches).toList()
            ..sort((a, b) {
              final cmp = switch (sortField) {
                _SortField.date => a.shipmentDate.compareTo(b.shipmentDate),
                _SortField.total => a.total.compareTo(b.total),
              };
              return sortAscending ? cmp : -cmp;
            });

          return SortableReportScaffold<SalesOrder, _SortField>(
            title: title,
            isLoading: state.isLoading,
            onRefresh: () => context.read<ReportBloc<SalesOrder>>().add(const RefreshReport()),
            rows: orders,
            sortField: sortField,
            sortAscending: sortAscending,
            onSort: (field) => context.read<ReportBloc<SalesOrder>>().add(SetSort(field)),
            emptyIcon: Icons.assignment_outlined,
            emptyTitle: 'No orders found',
            emptyMessage: 'No sales orders match this status right now.',
            columns: const [
              ReportColumn(
                label: 'ORDER / SHIP DATE',
                flex: 5,
                field: _SortField.date,
                alignEnd: false,
              ),
              ReportColumn(label: 'TOTAL', flex: 3, field: _SortField.total),
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
      ),
    );
  }
}
