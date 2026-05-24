import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../bloc/receipt_bloc.dart';
import 'receipt_editor_page.dart';

class ReceiptListPage extends StatefulWidget {
  const ReceiptListPage({super.key});

  @override
  State<ReceiptListPage> createState() => _ReceiptListPageState();
}

class _ReceiptListPageState extends State<ReceiptListPage> {
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    context.read<ReceiptBloc>().add(LoadReceipts());
  }

  Future<void> _selectDate(bool isStart, DateTime? current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: isDark
              ? ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: AppTheme.primaryIndigo,
                    onPrimary: Colors.white,
                    surface: AppTheme.darkSurface,
                    onSurface: AppTheme.darkText,
                  ),
                )
              : ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: AppTheme.primaryIndigo,
                    onPrimary: Colors.white,
                    surface: AppTheme.lightSurface,
                    onSurface: AppTheme.lightText,
                  ),
                ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      final bloc = context.read<ReceiptBloc>();
      if (isStart) {
        bloc.add(SetReceiptDateFilter(startDate: picked, endDate: bloc.state.endDate));
      } else {
        bloc.add(SetReceiptDateFilter(startDate: bloc.state.startDate, endDate: picked));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt Vouchers'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => context.read<ReceiptBloc>().add(LoadReceipts()),
          ),
        ],
      ),
      body: BlocConsumer<ReceiptBloc, ReceiptState>(
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(backgroundColor: AppTheme.errorRose, content: Text(state.errorMessage!)),
            );
            context.read<ReceiptBloc>().add(ClearReceiptMessages());
          }
          if (state.successMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  backgroundColor: AppTheme.successEmerald,
                  content: Text(state.successMessage!)),
            );
            context.read<ReceiptBloc>().add(ClearReceiptMessages());
          }
        },
        builder: (context, state) {
          final hasFilter = state.startDate != null || state.endDate != null;
          final list = state.filteredReceipts;

          return Column(
            children: [
              // Date filter card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Card(
                  elevation: isDark ? 0 : 2,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.filter_alt_outlined,
                                size: 18, color: AppTheme.primaryIndigo),
                            const SizedBox(width: 6),
                            const Text('Filter by Date Range',
                                style:
                                    TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const Spacer(),
                            if (hasFilter)
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => context
                                    .read<ReceiptBloc>()
                                    .add(const SetReceiptDateFilter()),
                                child: const Text('Clear',
                                    style: TextStyle(
                                        color: AppTheme.errorRose, fontSize: 12)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _DatePickerBox(
                                isDark: isDark,
                                label: state.startDate != null
                                    ? _dateFormat.format(state.startDate!)
                                    : 'Start Date',
                                hasValue: state.startDate != null,
                                onTap: () => _selectDate(true, state.startDate),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text('to', style: TextStyle(fontSize: 12)),
                            ),
                            Expanded(
                              child: _DatePickerBox(
                                isDark: isDark,
                                label: state.endDate != null
                                    ? _dateFormat.format(state.endDate!)
                                    : 'End Date',
                                hasValue: state.endDate != null,
                                onTap: () => _selectDate(false, state.endDate),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              if (state.isLoading)
                const Expanded(
                  child: Center(
                      child: CircularProgressIndicator(color: AppTheme.primaryIndigo)),
                )
              else if (list.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.payments_outlined,
                            size: 64,
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFCBD5E1)),
                        const SizedBox(height: 16),
                        Text(
                          'No receipts found',
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
                          hasFilter
                              ? 'Try expanding your date range.'
                              : 'Tap "+" to log a new payment receipt.',
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
                )
              else
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: ListView.separated(
                        padding: const EdgeInsets.only(
                            left: 16, right: 16, top: 8, bottom: 80),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final receipt = list[index];
                          return Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                context
                                    .read<ReceiptBloc>()
                                    .add(StartEditReceipt(receipt));
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const ReceiptEditorPage()),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor:
                                          AppTheme.successEmerald.withValues(alpha: 0.1),
                                      child: const Icon(Icons.payments_outlined,
                                          color: AppTheme.successEmerald),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                receipt.paymentNumber,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  color: AppTheme.primaryIndigo,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: receipt.isPendingSync
                                                      ? AppTheme.warningAmber
                                                          .withValues(alpha: 0.12)
                                                      : AppTheme.successEmerald
                                                          .withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  receipt.isPendingSync
                                                      ? 'Pending Sync'
                                                      : 'Synced',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: receipt.isPendingSync
                                                        ? AppTheme.warningAmber
                                                        : AppTheme.successEmerald,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(receipt.customerName,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13)),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${receipt.paymentMode}  •  ${_dateFormat.format(receipt.date)}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark
                                                  ? AppTheme.darkTextSecondary
                                                  : AppTheme.lightTextSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '₹${receipt.amount.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                            color: AppTheme.successEmerald,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.keyboard_arrow_right,
                                        color: isDark
                                            ? AppTheme.darkTextSecondary
                                            : AppTheme.lightTextSecondary),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Log New Receipt',
        backgroundColor: AppTheme.successEmerald,
        foregroundColor: Colors.white,
        onPressed: () {
          context.read<ReceiptBloc>().add(StartNewReceipt());
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ReceiptEditorPage()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _DatePickerBox extends StatelessWidget {
  final bool isDark;
  final String label;
  final bool hasValue;
  final VoidCallback onTap;

  const _DatePickerBox({
    required this.isDark,
    required this.label,
    required this.hasValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(8),
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        ),
        child: Row(
          children: [
            const Icon(Icons.date_range, size: 16, color: AppTheme.primaryIndigo),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: hasValue
                      ? (isDark ? AppTheme.darkText : AppTheme.lightText)
                      : (isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
