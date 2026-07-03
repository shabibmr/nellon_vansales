import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/utils/date_picker.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../../ui/core/utils/currency.dart';
import '../../../../ui/core/widgets/date_range_filter_card.dart';
import '../../../../ui/core/widgets/empty_state.dart';
import '../bloc/expense_bloc.dart';
import 'expense_editor_page.dart';

class ExpenseListPage extends StatefulWidget {
  const ExpenseListPage({super.key});

  @override
  State<ExpenseListPage> createState() => _ExpenseListPageState();
}

class _ExpenseListPageState extends State<ExpenseListPage> {
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    context.read<ExpenseBloc>().add(LoadExpenses());
  }

  Future<void> _selectDate(bool isStart, DateTime? current) async {
    final picked = await showThemedDatePicker(context, initialDate: current);
    if (picked != null && mounted) {
      final bloc = context.read<ExpenseBloc>();
      if (isStart) {
        bloc.add(
          SetExpenseDateFilter(startDate: picked, endDate: bloc.state.endDate),
        );
      } else {
        bloc.add(
          SetExpenseDateFilter(
            startDate: bloc.state.startDate,
            endDate: picked,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Van Expenses'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => context.read<ExpenseBloc>().add(LoadExpenses()),
          ),
        ],
      ),
      body: BlocConsumer<ExpenseBloc, ExpenseState>(
        listener: (context, state) {
          if (state.errorMessage != null) {
            showErrorSnackBar(context, state.errorMessage!);
            context.read<ExpenseBloc>().add(ClearExpenseMessages());
          }
          if (state.successMessage != null) {
            showSuccessSnackBar(context, state.successMessage!);
            context.read<ExpenseBloc>().add(ClearExpenseMessages());
          }
        },
        builder: (context, state) {
          final hasFilter = state.startDate != null || state.endDate != null;
          final list = state.filteredExpenses;

          return Column(
            children: [
              DateRangeFilterCard(
                startDate: state.startDate,
                endDate: state.endDate,
                onStartTap: () => _selectDate(true, state.startDate),
                onEndTap: () => _selectDate(false, state.endDate),
                onClear: hasFilter
                    ? () => context.read<ExpenseBloc>().add(
                        const SetExpenseDateFilter(),
                      )
                    : null,
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
                  child: EmptyState(
                    icon: Icons.receipt_outlined,
                    title: 'No expenses found',
                    message: hasFilter
                        ? 'Try expanding your date range.'
                        : 'Tap "+" to log your first expense.',
                  ),
                )
              else
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: ListView.separated(
                        padding: const EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 8,
                          bottom: 80,
                        ),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final expense = list[index];
                          final firstLine = expense.lines.isNotEmpty
                              ? expense.lines.first
                              : null;
                          final category = firstLine?.category ?? '';
                          final description = firstLine?.description ?? '';

                          return Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                context.read<ExpenseBloc>().add(
                                  StartEditExpense(expense),
                                );
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ExpenseEditorPage(),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: AppTheme.errorRose
                                          .withValues(alpha: 0.1),
                                      child: const Icon(
                                        Icons.local_gas_station_outlined,
                                        color: AppTheme.errorRose,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                _dateFormat.format(
                                                  expense.date,
                                                ),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: expense.isPendingSync
                                                      ? AppTheme.warningAmber
                                                            .withValues(
                                                              alpha: 0.12,
                                                            )
                                                      : AppTheme.successEmerald
                                                            .withValues(
                                                              alpha: 0.12,
                                                            ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  expense.isPendingSync
                                                      ? 'Pending Sync'
                                                      : 'Synced',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: expense.isPendingSync
                                                        ? AppTheme.warningAmber
                                                        : AppTheme
                                                              .successEmerald,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          if (category.isNotEmpty)
                                            Text(
                                              category,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: isDark
                                                    ? AppTheme.darkTextSecondary
                                                    : AppTheme
                                                          .lightTextSecondary,
                                              ),
                                            ),
                                          if (description.isNotEmpty)
                                            Text(
                                              description,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark
                                                    ? AppTheme.darkTextSecondary
                                                    : AppTheme
                                                          .lightTextSecondary,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          formatCurrency(expense.amount, cs),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                            color: AppTheme.errorRose,
                                          ),
                                        ),
                                        if (expense.receiptImagePath != null)
                                          const Icon(
                                            Icons.attach_file_rounded,
                                            size: 14,
                                            color: AppTheme.primaryIndigo,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.keyboard_arrow_right,
                                      color: isDark
                                          ? AppTheme.darkTextSecondary
                                          : AppTheme.lightTextSecondary,
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
        tooltip: 'Log New Expense',
        backgroundColor: AppTheme.errorRose,
        foregroundColor: Colors.white,
        onPressed: () {
          context.read<ExpenseBloc>().add(StartNewExpense());
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ExpenseEditorPage()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
