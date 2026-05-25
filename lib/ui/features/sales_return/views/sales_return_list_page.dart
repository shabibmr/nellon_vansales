import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../bloc/sales_return_bloc.dart';
import 'sales_return_editor_page.dart';

/// Screen listing all recorded Sales Returns (Credit Notes).
class SalesReturnListPage extends StatefulWidget {
  const SalesReturnListPage({super.key});

  @override
  State<SalesReturnListPage> createState() => _SalesReturnListPageState();
}

class _SalesReturnListPageState extends State<SalesReturnListPage> {
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    context.read<SalesReturnBloc>().add(LoadReturns());
  }

  Future<void> _selectDate(bool isStart, DateTime? current) async {
    final initialDate = current ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: isDark
              ? ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: AppTheme.warningAmber,
                    onPrimary: Colors.white,
                    surface: AppTheme.darkSurface,
                    onSurface: AppTheme.darkText,
                  ),
                )
              : ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: AppTheme.warningAmber,
                    onPrimary: Colors.white,
                    surface: AppTheme.lightSurface,
                    onSurface: AppTheme.lightText,
                  ),
                ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != current && mounted) {
      final bloc = context.read<SalesReturnBloc>();
      if (isStart) {
        bloc.add(SetReturnDateFilter(startDate: picked, endDate: bloc.state.endDate));
      } else {
        bloc.add(SetReturnDateFilter(startDate: bloc.state.startDate, endDate: picked));
      }
    }
  }

  void _clearFilters() {
    context.read<SalesReturnBloc>().add(const SetReturnDateFilter(startDate: null, endDate: null));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Returns'),
        actions: [
          IconButton(
            tooltip: 'Reload Returns',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => context.read<SalesReturnBloc>().add(LoadReturns()),
          ),
        ],
      ),
      body: BlocConsumer<SalesReturnBloc, SalesReturnState>(
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(backgroundColor: AppTheme.errorRose, content: Text(state.errorMessage!)),
            );
            context.read<SalesReturnBloc>().add(ClearReturnMessages());
          }
          if (state.successMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(backgroundColor: AppTheme.successEmerald, content: Text(state.successMessage!)),
            );
            context.read<SalesReturnBloc>().add(ClearReturnMessages());
          }
        },
        builder: (context, state) {
          final hasFilter = state.startDate != null || state.endDate != null;
          final list = state.filteredReturns;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Card(
                  elevation: isDark ? 0 : 2,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.filter_alt_outlined, size: 18, color: AppTheme.warningAmber),
                            const SizedBox(width: 6),
                            const Text(
                              'Filter by Date Range',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const Spacer(),
                            if (hasFilter)
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: _clearFilters,
                                child: const Text('Clear', style: TextStyle(color: AppTheme.errorRose, fontSize: 12)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => _selectDate(true, state.startDate),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.date_range, size: 16, color: AppTheme.warningAmber),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          state.startDate != null ? _dateFormat.format(state.startDate!) : 'Start Date',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: state.startDate != null
                                                ? (isDark ? AppTheme.darkText : AppTheme.lightText)
                                                : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8.0),
                              child: Text('to', style: TextStyle(fontSize: 12)),
                            ),
                            Expanded(
                              child: InkWell(
                                onTap: () => _selectDate(false, state.endDate),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.date_range, size: 16, color: AppTheme.warningAmber),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          state.endDate != null ? _dateFormat.format(state.endDate!) : 'End Date',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: state.endDate != null
                                                ? (isDark ? AppTheme.darkText : AppTheme.lightText)
                                                : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
                  child: Center(child: CircularProgressIndicator(color: AppTheme.warningAmber)),
                )
              else if (list.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.assignment_return_outlined,
                          size: 64,
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No returns found',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          hasFilter
                              ? 'Try expanding your date range filters.'
                              : 'Click "+" below to log a sales return.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
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
                        padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 80.0, top: 8.0),
                        itemCount: list.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final ret = list[index];

                          return Card(
                            child: InkWell(
                              onTap: () {
                                context.read<SalesReturnBloc>().add(StartEditReturn(ret));
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const SalesReturnEditorPage(),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                ret.creditNoteNumber,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                  color: AppTheme.warningAmber,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: ret.isPendingSync
                                                      ? AppTheme.warningAmber.withValues(alpha: 0.12)
                                                      : AppTheme.successEmerald.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  ret.isPendingSync ? 'Pending Sync' : 'Synced',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: ret.isPendingSync
                                                        ? AppTheme.warningAmber
                                                        : AppTheme.successEmerald,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            ret.customerName,
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Date: ${_dateFormat.format(ret.date)}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                            ),
                                          ),
                                          if (ret.reason.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Reason: ${ret.reason}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontStyle: FontStyle.italic,
                                                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '$cs${ret.total.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                            color: AppTheme.warningAmber,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${ret.items.length} items',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.keyboard_arrow_right,
                                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                    ),
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
        tooltip: 'Create New Sales Return',
        backgroundColor: AppTheme.warningAmber,
        foregroundColor: Colors.white,
        onPressed: () {
          context.read<SalesReturnBloc>().add(StartNewReturn());
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SalesReturnEditorPage()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
