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
import '../../../core/widgets/empty_state.dart';

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

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;
    final orders = _allOrders.where(_matches).toList()
      ..sort((a, b) => b.shipmentDate.compareTo(a.shipmentDate));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Refresh from Zoho',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _fetchFromZoho,
            ),
        ],
      ),
      body: SafeArea(
        child: orders.isEmpty
            ? const EmptyState(
                icon: Icons.assignment_outlined,
                title: 'No orders found',
                message: 'No sales orders match this status right now.',
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: orders.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final order = orders[index];
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
              ),
      ),
    );
  }
}
