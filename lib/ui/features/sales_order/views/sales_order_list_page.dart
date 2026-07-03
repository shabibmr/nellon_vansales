import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/utils/currency.dart';
import '../../../../ui/core/utils/date_picker.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../../ui/core/widgets/date_range_filter_card.dart';
import '../../../../ui/core/widgets/document_list_card.dart';
import '../../../../ui/core/widgets/empty_state.dart';
import '../bloc/sales_order_bloc.dart';
import 'sales_order_editor_page.dart';

class SalesOrderListPage extends StatefulWidget {
  const SalesOrderListPage({super.key});

  @override
  State<SalesOrderListPage> createState() => _SalesOrderListPageState();
}

class _SalesOrderListPageState extends State<SalesOrderListPage> {
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    context.read<SalesOrderBloc>().add(LoadOrders());
  }

  Future<void> _selectDate(bool isStart, DateTime? current) async {
    final picked = await showThemedDatePicker(
      context,
      initialDate: current ?? DateTime.now(),
    );
    if (picked != null && picked != current && mounted) {
      final bloc = context.read<SalesOrderBloc>();
      if (isStart) {
        bloc.add(SetDateFilter(startDate: picked, endDate: bloc.state.endDate));
      } else {
        bloc.add(
          SetDateFilter(startDate: bloc.state.startDate, endDate: picked),
        );
      }
    }
  }

  void _clearFilters() {
    context.read<SalesOrderBloc>().add(
      const SetDateFilter(startDate: null, endDate: null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Orders'),
        actions: [
          IconButton(
            tooltip: 'Sync Orders from Zoho',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                context.read<SalesOrderBloc>().add(RefreshOrdersFromZoho()),
          ),
        ],
      ),
      body: BlocConsumer<SalesOrderBloc, SalesOrderState>(
        listener: (context, state) {
          if (state.errorMessage != null) {
            showErrorSnackBar(context, state.errorMessage!);
            context.read<SalesOrderBloc>().add(ClearMessages());
          }
          if (state.successMessage != null) {
            showSuccessSnackBar(context, state.successMessage!);
            context.read<SalesOrderBloc>().add(ClearMessages());
          }
        },
        builder: (context, state) {
          final hasFilter = state.startDate != null || state.endDate != null;
          final list = state.filteredOrders;

          return Column(
            children: [
              DateRangeFilterCard(
                startDate: state.startDate,
                endDate: state.endDate,
                onStartTap: () => _selectDate(true, state.startDate),
                onEndTap: () => _selectDate(false, state.endDate),
                onClear: _clearFilters,
              ),

              if (state.isLoading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryIndigo,
                    ),
                  ),
                )
              else if (list.isEmpty)
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async => context.read<SalesOrderBloc>().add(
                      RefreshOrdersFromZoho(),
                    ),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: EmptyState(
                            icon: Icons.assignment_outlined,
                            title: 'No orders found',
                            message: hasFilter
                                ? 'Try expanding your date range filters.'
                                : 'Click "+" below to generate your first sales order.',
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: RefreshIndicator(
                        onRefresh: () async => context
                            .read<SalesOrderBloc>()
                            .add(RefreshOrdersFromZoho()),
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(
                            left: 16.0,
                            right: 16.0,
                            bottom: 80.0,
                            top: 8.0,
                          ),
                          itemCount: list.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final order = list[index];
                            return DocumentListCard(
                              docNumber: order.orderNumber,
                              customerName: order.customerName,
                              date: _dateFormat.format(order.date),
                              total: formatCurrency(order.total, cs),
                              itemCount: order.items.length,
                              isPendingSync: order.isPendingSync,
                              extraBadgeLabel: order.isConverted
                                  ? 'Converted'
                                  : null,
                              onTap: () {
                                context.read<SalesOrderBloc>().add(
                                  StartEditOrder(order),
                                );
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const SalesOrderEditorPage(),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Create New Sales Order',
        backgroundColor: AppTheme.primaryIndigo,
        foregroundColor: Colors.white,
        onPressed: () {
          context.read<SalesOrderBloc>().add(StartNewOrder());
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const SalesOrderEditorPage(),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
