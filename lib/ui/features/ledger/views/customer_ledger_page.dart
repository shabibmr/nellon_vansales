import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../domain/models/customer_ledger.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/utils/date_picker.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../bloc/customer_ledger_bloc.dart';

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
              // --- Filter Panel ---
              Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  elevation: isDark ? 0 : 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Customer selector
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => _showCustomerSelector(context, isDark),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFE2E8F0),
                              ),
                              borderRadius: BorderRadius.circular(10),
                              color: isDark
                                  ? const Color(0xFF0F172A)
                                  : const Color(0xFFF8FAFC),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.person_search_outlined,
                                  color: AppTheme.primaryIndigo,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        state.selectedCustomer?.name ??
                                            'Select Customer',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: state.selectedCustomer != null
                                              ? (isDark
                                                    ? AppTheme.darkText
                                                    : AppTheme.lightText)
                                              : (isDark
                                                    ? AppTheme.darkTextSecondary
                                                    : AppTheme
                                                          .lightTextSecondary),
                                        ),
                                      ),
                                      if (state.selectedCustomer != null &&
                                          state
                                              .selectedCustomer!
                                              .companyName
                                              .isNotEmpty)
                                        Text(
                                          state.selectedCustomer!.companyName,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark
                                                ? AppTheme.darkTextSecondary
                                                : AppTheme.lightTextSecondary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_drop_down,
                                  color: isDark
                                      ? AppTheme.darkTextSecondary
                                      : AppTheme.lightTextSecondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Date range
                        Row(
                          children: [
                            Expanded(
                              child: _DateBox(
                                isDark: isDark,
                                label: _dateFormat.format(state.startDate),
                                icon: Icons.date_range,
                                onTap: () => _pickDate(isStart: true),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text('to', style: TextStyle(fontSize: 12)),
                            ),
                            Expanded(
                              child: _DateBox(
                                isDark: isDark,
                                label: _dateFormat.format(state.endDate),
                                icon: Icons.date_range,
                                onTap: () => _pickDate(isStart: false),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Fetch button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: state.canFetch
                                ? () => context.read<CustomerLedgerBloc>().add(
                                    FetchLedger(),
                                  )
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryIndigo,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: state.isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.cloud_download_outlined,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                            label: Text(
                              state.isLoading
                                  ? 'Fetching from Zoho...'
                                  : 'Fetch Ledger Report',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // --- Report Body ---
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

// --- Report Content ---

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
    final cs = context.org.currencySymbol;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            // Customer + balance summary
            Card(
              color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person, color: AppTheme.primaryIndigo),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ledger.customerName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 4 summary chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _SummaryChip(
                          label: 'Opening Balance',
                          value:
                              '$cs${ledger.openingBalance.toStringAsFixed(2)}',
                          color: AppTheme.primaryIndigo,
                          isDark: isDark,
                        ),
                        _SummaryChip(
                          label: 'Total Invoiced',
                          value: '$cs${ledger.totalDebits.toStringAsFixed(2)}',
                          color: AppTheme.warningAmber,
                          isDark: isDark,
                        ),
                        _SummaryChip(
                          label: 'Total Received',
                          value: '$cs${ledger.totalCredits.toStringAsFixed(2)}',
                          color: AppTheme.successEmerald,
                          isDark: isDark,
                        ),
                        _SummaryChip(
                          label: 'Closing Balance',
                          value:
                              '$cs${ledger.closingBalance.toStringAsFixed(2)}',
                          color: ledger.closingBalance > 0
                              ? AppTheme.errorRose
                              : AppTheme.successEmerald,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Transactions header
            Row(
              children: [
                const Icon(
                  Icons.list_alt_outlined,
                  size: 16,
                  color: AppTheme.primaryIndigo,
                ),
                const SizedBox(width: 6),
                Text(
                  'Transactions  (${ledger.transactions.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (ledger.transactions.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'No transactions in this period.',
                    style: TextStyle(
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                  ),
                ),
              )
            else
              // Ledger table header
              Column(
                children: [
                  _TableHeader(isDark: isDark),
                  const Divider(height: 1),
                  ...ledger.transactions.map(
                    (tx) => _TransactionRow(
                      tx: tx,
                      isDark: isDark,
                      shortDate: shortDate,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  final bool isDark;
  const _TableHeader({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
    );
    return Container(
      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text('DATE', style: style)),
          Expanded(child: Text('DESCRIPTION', style: style)),
          SizedBox(
            width: 72,
            child: Text('DEBIT', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 72,
            child: Text('CREDIT', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 80,
            child: Text('BALANCE', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final LedgerTransaction tx;
  final bool isDark;
  final DateFormat shortDate;

  const _TransactionRow({
    required this.tx,
    required this.isDark,
    required this.shortDate,
  });

  Color get _typeColor {
    switch (tx.type) {
      case 'invoice':
      case 'debit_note':
        return AppTheme.warningAmber;
      case 'payment':
      case 'credit_note':
        return AppTheme.successEmerald;
      default:
        return AppTheme.primaryIndigo;
    }
  }

  IconData get _typeIcon {
    switch (tx.type) {
      case 'invoice':
        return Icons.receipt_long_outlined;
      case 'payment':
        return Icons.payments_outlined;
      case 'credit_note':
        return Icons.remove_circle_outline;
      case 'debit_note':
        return Icons.add_circle_outline;
      default:
        return Icons.swap_horiz_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;
    final textStyle = TextStyle(
      fontSize: 12,
      color: isDark ? AppTheme.darkText : AppTheme.lightText,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 60,
                child: Text(
                  shortDate.format(tx.date),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Icon(_typeIcon, size: 14, color: _typeColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tx.description.isNotEmpty
                                ? tx.description
                                : tx.transactionNumber,
                            style: textStyle.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (tx.transactionNumber.isNotEmpty &&
                              tx.description != tx.transactionNumber)
                            Text(
                              tx.transactionNumber,
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark
                                    ? AppTheme.darkTextSecondary
                                    : AppTheme.lightTextSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  tx.debit > 0 ? '$cs${tx.debit.toStringAsFixed(2)}' : '-',
                  style: textStyle.copyWith(
                    color: tx.debit > 0
                        ? AppTheme.warningAmber
                        : Colors.transparent,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  tx.credit > 0 ? '$cs${tx.credit.toStringAsFixed(2)}' : '-',
                  style: textStyle.copyWith(
                    color: tx.credit > 0
                        ? AppTheme.successEmerald
                        : Colors.transparent,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  '$cs${tx.balance.toStringAsFixed(2)}',
                  style: textStyle.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: isDark ? AppTheme.darkText : AppTheme.lightText,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  final bool isDark;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _DateBox({
    required this.isDark,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
          borderRadius: BorderRadius.circular(8),
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppTheme.primaryIndigo),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppTheme.darkText : AppTheme.lightText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
