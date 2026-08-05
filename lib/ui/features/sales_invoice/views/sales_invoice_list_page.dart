import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../domain/models/sales_invoice.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/date_picker.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/date_range_filter_card.dart';
import '../../../core/widgets/document_list_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../bloc/sales_invoice_list_bloc.dart';
import '../bloc/sales_invoice_list_event.dart';
import '../bloc/sales_invoice_list_state.dart';
import 'sales_invoice_editor_page.dart';

class SalesInvoiceListPage extends StatefulWidget {
  const SalesInvoiceListPage({super.key});

  @override
  State<SalesInvoiceListPage> createState() => _SalesInvoiceListPageState();
}

class _SalesInvoiceListPageState extends State<SalesInvoiceListPage> {
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  static String? _statusBadgeLabel(String status) {
    final s = status.trim();
    if (s.isEmpty) return null;
    return s
        .split('_')
        .where((p) => p.isNotEmpty)
        .map((p) => '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}')
        .join(' ');
  }

  static Color _statusBadgeColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return AppTheme.successEmerald;
      case 'overdue':
        return AppTheme.errorRose;
      case 'partially_paid':
        return AppTheme.warningAmber;
      case 'void':
      case 'draft':
        return AppTheme.lightTextSecondary;
      default:
        return AppTheme.primaryIndigo;
    }
  }

  @override
  void initState() {
    super.initState();
    context.read<SalesInvoiceListBloc>().add(const LoadInvoices());
  }

  Future<void> _selectDate(bool isStart, DateTime? current) async {
    final picked = await showThemedDatePicker(
      context,
      initialDate: current ?? DateTime.now(),
    );
    if (picked != null && picked != current && mounted) {
      final bloc = context.read<SalesInvoiceListBloc>();
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
    context.read<SalesInvoiceListBloc>().add(
      const SetDateFilter(startDate: null, endDate: null),
    );
  }

  Future<void> _openEditor({
    required bool readOnly,
    SalesInvoice? invoice,
  }) async {
    await SalesInvoiceEditorPage.open(
      context,
      invoice: invoice,
      readOnly: readOnly,
    );
    if (mounted) {
      context.read<SalesInvoiceListBloc>().add(const LoadInvoices());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Invoices'),
        actions: [
          IconButton(
            tooltip: 'Reload Invoices',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => context
                .read<SalesInvoiceListBloc>()
                .add(const RefreshInvoicesFromZoho()),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocConsumer<SalesInvoiceListBloc, SalesInvoiceListState>(
          listenWhen: (previous, current) =>
              previous.errorMessage != current.errorMessage ||
              previous.successMessage != current.successMessage,
          listener: (context, state) {
            if (state.errorMessage != null) {
              showErrorSnackBar(context, state.errorMessage!);
              context
                  .read<SalesInvoiceListBloc>()
                  .add(const ClearInvoiceListMessages());
            }
            if (state.successMessage != null) {
              showSuccessSnackBar(context, state.successMessage!);
              context
                  .read<SalesInvoiceListBloc>()
                  .add(const ClearInvoiceListMessages());
            }
          },
          builder: (context, state) {
            final hasFilter = state.startDate != null || state.endDate != null;
            final list = state.filteredInvoices;
            final loading = state.status == SalesInvoiceListStatus.loading;

            return Column(
              children: [
                DateRangeFilterCard(
                  startDate: state.startDate,
                  endDate: state.endDate,
                  onStartTap: () => _selectDate(true, state.startDate),
                  onEndTap: () => _selectDate(false, state.endDate),
                  onClear: _clearFilters,
                ),
                if (loading)
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
                      onRefresh: () async => context
                          .read<SalesInvoiceListBloc>()
                          .add(const RefreshInvoicesFromZoho()),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.6,
                            child: EmptyState(
                              icon: Icons.receipt_long_rounded,
                              title: 'No invoices found',
                              message: hasFilter
                                  ? 'Try expanding your date range filters.'
                                  : 'Click "+" below to generate your first invoice.',
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
                              .read<SalesInvoiceListBloc>()
                              .add(const RefreshInvoicesFromZoho()),
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
                              final invoice = list[index];
                              final statusLabel = _statusBadgeLabel(
                                invoice.status,
                              );
                              return DocumentListCard(
                                key: ValueKey(invoice.id),
                                docNumber: invoice.invoiceNumber,
                                customerName: invoice.customerName,
                                date: _dateFormat.format(invoice.date),
                                total: formatCurrency(invoice.total, cs),
                                itemCount: invoice.items.isNotEmpty
                                    ? invoice.items.length
                                    : null,
                                isPendingSync: invoice.isPendingSync,
                                extraBadgeLabel: statusLabel,
                                extraBadgeColor: _statusBadgeColor(
                                  invoice.status,
                                ),
                                onTap: () => _openEditor(
                                  invoice: invoice,
                                  readOnly: true,
                                ),
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
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Create New Sales Invoice',
        backgroundColor: AppTheme.primaryIndigo,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(readOnly: false, invoice: null),
        child: const Icon(Icons.add),
      ),
    );
  }
}
