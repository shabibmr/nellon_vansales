import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../data/services/report_export_service.dart';
import '../../../../domain/models/customer_ledger.dart';
import '../../../../ui/core/cubit/salesperson_cubit.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/utils/date_picker.dart';
import '../../../../ui/core/utils/error_mapper.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../print_settings/cubit/print_settings_cubit.dart';
import '../../thermal_print/cubit/thermal_printer_cubit.dart';
import '../../thermal_print/widgets/thermal_print_preview_dialog.dart';
import '../bloc/customer_ledger_bloc.dart';
import '../utils/open_ledger_transaction.dart';
import '../widgets/customer_ledger_header.dart';
import '../widgets/ledger_filter_header.dart';
import '../widgets/ledger_transaction_table.dart';

class CustomerLedgerPage extends StatefulWidget {
  const CustomerLedgerPage({super.key});

  @override
  State<CustomerLedgerPage> createState() => _CustomerLedgerPageState();
}

class _CustomerLedgerPageState extends State<CustomerLedgerPage> {
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  final DateFormat _shortDate = DateFormat('dd MMM yy');

  Future<void> _pickDate({required bool isStart}) async {
    final state = context.read<CustomerLedgerBloc>().state;
    final current = isStart ? state.startDate : state.endDate;
    final picked = await showThemedDatePicker(
      context,
      initialDate: current,
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      if (isStart) {
        context.read<CustomerLedgerBloc>().add(SetLedgerStartDate(picked));
      } else {
        context.read<CustomerLedgerBloc>().add(SetLedgerEndDate(picked));
      }
    }
  }

  void _showCustomerSelector(BuildContext context, bool isDark) {
    final cs = context.org.currencySymbol;
    final bloc = context.read<CustomerLedgerBloc>();
    final allCustomers = bloc.customers;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        var filtered = allCustomers;
        final searchCtrl = TextEditingController();

        return StatefulBuilder(
          builder: (sheetCtx, setModal) {
            void onSearch(String query) {
              final q = query.toLowerCase();
              setModal(() {
                filtered = q.isEmpty
                    ? allCustomers
                    : allCustomers.where((c) {
                        return c.name.toLowerCase().contains(q) ||
                            c.companyName.toLowerCase().contains(q) ||
                            c.phone.contains(query);
                      }).toList();
              });
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (_, scrollCtrl) {
                return Column(
                  children: [
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Select Customer',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: TextField(
                        controller: searchCtrl,
                        autofocus: true,
                        onChanged: onSearch,
                        decoration: InputDecoration(
                          hintText: 'Search by name, company or phone...',
                          prefixIcon: const Icon(
                            Icons.search,
                            color: AppTheme.primaryIndigo,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                'No customers found',
                                style: TextStyle(
                                  color: isDark
                                      ? AppTheme.darkTextSecondary
                                      : AppTheme.lightTextSecondary,
                                ),
                              ),
                            )
                          : ListView.separated(
                              controller: scrollCtrl,
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final customer = filtered[i];
                                return ListTile(
                                  title: Text(
                                    customer.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(customer.companyName),
                                  trailing: customer.outstandingBalance > 0
                                      ? Text(
                                          '$cs${customer.outstandingBalance.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            color: AppTheme.errorRose,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        )
                                      : null,
                                  onTap: () {
                                    context.read<CustomerLedgerBloc>().add(
                                      SetLedgerCustomer(customer),
                                    );
                                    Navigator.pop(sheetCtx);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _handleLedgerExport(
    BuildContext context,
    CustomerLedger ledger,
    CustomerLedgerState state,
    String action,
  ) async {
    final cs = context.org.currencySymbol;
    final headers = const [
      'Date',
      'Doc No',
      'Type',
      'Debit',
      'Credit',
      'Balance',
    ];
    final data = ledger.transactions
        .map((t) => [
              _shortDate.format(t.date),
              t.transactionNumber.isNotEmpty ? t.transactionNumber : '-',
              t.type.toUpperCase(),
              t.debit > 0 ? t.debit.toStringAsFixed(2) : '-',
              t.credit > 0 ? t.credit.toStringAsFixed(2) : '-',
              t.balance.toStringAsFixed(2),
            ])
        .toList();

    final title = 'Customer Ledger - ${ledger.customerName}';
    final dateRange =
        '${_dateFormat.format(state.startDate)} to ${_dateFormat.format(state.endDate)}';
    final stats = {
      'Opening Bal': '$cs${ledger.openingBalance.toStringAsFixed(2)}',
      'Total Debits': '$cs${ledger.totalDebits.toStringAsFixed(2)}',
      'Total Credits': '$cs${ledger.totalCredits.toStringAsFixed(2)}',
      'Closing Bal': '$cs${ledger.closingBalance.toStringAsFixed(2)}',
    };

    try {
      switch (action) {
        case 'thermal':
          final org = context.org.state;
          if (org == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No organization details found')),
            );
            return;
          }
          final salesperson = context.read<SalespersonCubit>().state;
          final supervisorPhone = context.read<PrintSettingsCubit>().supervisorPhone;
          final printerCubit = context.read<ThermalPrinterCubit>();
          final preview = await printerCubit.previewReport(
            title: 'CUSTOMER LEDGER',
            subtitle: 'Customer: ${ledger.customerName}',
            headers: headers,
            rows: data,
            org: org,
            dateRangeText: dateRange,
            summaryStats: stats,
            salespersonName: salesperson?.name,
            salespersonPhone: salesperson?.phone,
            supervisorPhone: supervisorPhone,
          );
          if (!context.mounted) return;
          await ThermalPrintPreviewDialog.show(
            context,
            preview: preview,
            onPrint: () {
              printerCubit.printReport(
                title: 'CUSTOMER LEDGER',
                subtitle: 'Customer: ${ledger.customerName}',
                headers: headers,
                rows: data,
                org: org,
                dateRangeText: dateRange,
                summaryStats: stats,
                salespersonName: salesperson?.name,
                salespersonPhone: salesperson?.phone,
                supervisorPhone: supervisorPhone,
              );
            },
          );
          break;
        case 'print':
          await ReportExportService.printReport(title, headers, data);
          break;
        case 'pdf':
          await ReportExportService.exportPdf(title, headers, data);
          break;
        case 'csv':
          await ReportExportService.exportCsv(title, headers, data);
          break;
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action failed: ${userFacingMessage(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Ledger'),
        actions: [
          BlocBuilder<CustomerLedgerBloc, CustomerLedgerState>(
            builder: (context, state) {
              if (state.ledger == null) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Clear Report',
                    icon: const Icon(Icons.clear_all_rounded),
                    onPressed: () =>
                        context.read<CustomerLedgerBloc>().add(ClearLedger()),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Export / Print ledger',
                    icon: const Icon(Icons.ios_share_rounded),
                    onSelected: (action) => _handleLedgerExport(
                      context,
                      state.ledger!,
                      state,
                      action,
                    ),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'thermal',
                        child: Row(
                          children: [
                            Icon(Icons.receipt_long_rounded, size: 18),
                            SizedBox(width: 10),
                            Text('Thermal Print (Bluetooth)'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'print',
                        child: Row(
                          children: [
                            Icon(Icons.print_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Print (A4 / Spooler)'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'pdf',
                        child: Row(
                          children: [
                            Icon(Icons.picture_as_pdf_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Export as PDF'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'csv',
                        child: Row(
                          children: [
                            Icon(Icons.grid_on_rounded, size: 18),
                            SizedBox(width: 10),
                            Text('Export as Excel (CSV)'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: BlocConsumer<CustomerLedgerBloc, CustomerLedgerState>(
          listenWhen: (p, c) => p.errorMessage != c.errorMessage,
          listener: (context, state) {
            if (state.errorMessage != null) {
              showErrorSnackBar(context, state.errorMessage!);
            }
          },
          builder: (context, state) {
            return Column(
              children: [
                LedgerFilterHeader(
                  state: state,
                  isDark: isDark,
                  dateFormat: _dateFormat,
                  onSelectCustomer: () => _showCustomerSelector(context, isDark),
                  onPickStartDate: () => _pickDate(isStart: true),
                  onPickEndDate: () => _pickDate(isStart: false),
                  onFetch: () => context.read<CustomerLedgerBloc>().add(
                        FetchLedger(),
                      ),
                ),
                if (state.ledger != null)
                  Expanded(
                    child: _LedgerReportView(
                      ledger: state.ledger!,
                      isDark: isDark,
                      dateFormat: _dateFormat,
                      shortDate: _shortDate,
                    ),
                  )
                else if (!state.isLoading)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.account_balance_outlined,
                            size: 64,
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFCBD5E1),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No report loaded',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Select a customer and tap "Fetch Ledger Report".',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFF475569)
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LedgerReportView extends StatelessWidget {
  final CustomerLedger ledger;
  final bool isDark;
  final DateFormat dateFormat;
  final DateFormat shortDate;

  const _LedgerReportView({
    required this.ledger,
    required this.isDark,
    required this.dateFormat,
    required this.shortDate,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            CustomerLedgerHeader(
              ledger: ledger,
              isDark: isDark,
            ),
            const SizedBox(height: 12),
            LedgerTransactionTable(
              transactions: ledger.transactions,
              isDark: isDark,
              shortDate: shortDate,
              onTransactionTap: (tx) => openLedgerTransaction(context, tx),
            ),
          ],
        ),
      ),
    );
  }
}
