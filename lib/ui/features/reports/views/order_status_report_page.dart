import 'package:flutter/material.dart';
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
class OrderStatusReportPage extends StatefulWidget {
  final OrderStatusFilter filter;
  final String title;

  const OrderStatusReportPage({
    super.key,
    required this.filter,
    required this.title,
  });

  @override
  State<OrderStatusReportPage> createState() => _OrderStatusReportPageState();
}

class _OrderStatusReportPageState extends State<OrderStatusReportPage> {
  final HiveDatabaseService _db = sl<HiveDatabaseService>();
  final ZohoApiClient _apiClient = sl<ZohoApiClient>();
  final DateFormat _dateFmt = DateFormat('dd MMM yyyy');

  _SortField _sortField = _SortField.date;
  bool _sortAscending = false;
  bool _isLoading = false;
  List<SalesOrder> _allOrders = [];

  @override
  void initState() {
    super.initState();
    _allOrders = _db.getLocalOrders();
    _fetchFromZoho();
  }

  Future<void> _fetchFromZoho() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final raw = await _apiClient.fetchSalesOrders();
      final orders = raw.map((json) => SalesOrderModel.fromJson(json)).toList();
      if (!mounted) return;
      setState(() {
        _allOrders = orders;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showErrorSnackBar(context, 'Could not load report from Zoho: $e');
    }
  }

  bool _matches(SalesOrder order) {
    final today = DateTime.now();
    final shipDay = DateTime(
      order.shipmentDate.year,
      order.shipmentDate.month,
      order.shipmentDate.day,
    );
    final todayDay = DateTime(today.year, today.month, today.day);

    switch (widget.filter) {
      case OrderStatusFilter.invoiced:
        return order.isConverted;
      case OrderStatusFilter.delayed:
        return !order.isConverted && shipDay.isBefore(todayDay);
      case OrderStatusFilter.readyOrPending:
        return !order.isConverted && !shipDay.isBefore(todayDay);
    }
  }

  void _toggleSort(_SortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAscending = !_sortAscending;
      } else {
        _sortField = field;
        _sortAscending = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;
    final orders = _allOrders.where(_matches).toList()
      ..sort((a, b) {
        final cmp = switch (_sortField) {
          _SortField.date => a.shipmentDate.compareTo(b.shipmentDate),
          _SortField.total => a.total.compareTo(b.total),
        };
        return _sortAscending ? cmp : -cmp;
      });

    return SortableReportScaffold<SalesOrder, _SortField>(
      title: widget.title,
      isLoading: _isLoading,
      onRefresh: _fetchFromZoho,
      rows: orders,
      sortField: _sortField,
      sortAscending: _sortAscending,
      onSort: _toggleSort,
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
        _dateFmt.format(order.date),
        _dateFmt.format(order.shipmentDate),
        order.total.toStringAsFixed(2),
        order.isConverted ? 'Invoiced' : 'Open',
      ],
      itemBuilder: (context, order) {
        return DocumentListCard(
          docNumber: order.orderNumber,
          customerName: order.customerName,
          date: _dateFmt.format(order.date),
          subtitle: 'Ship: ${_dateFmt.format(order.shipmentDate)}',
          total: '$cs${order.total.toStringAsFixed(2)}',
          itemCount: order.items.length,
          isPendingSync: order.isPendingSync,
          extraBadgeLabel: order.isConverted ? 'Invoiced' : null,
          onTap: () {},
        );
      },
    );
  }
}
