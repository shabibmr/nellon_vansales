import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../domain/models/customer_ledger.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/utils/date_picker.dart';
import '../../../../ui/core/utils/snackbars.dart';
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

    showModalBottomSheet(
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
              return IconButton(
                tooltip: 'Clear Report',
                icon: const Icon(Icons.clear_all_rounded),
                onPressed: () =>
                    context.read<CustomerLedgerBloc>().add(ClearLedger()),
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
