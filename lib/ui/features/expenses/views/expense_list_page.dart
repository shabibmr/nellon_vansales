import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../domain/models/expense_entry.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/date_picker.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/date_range_filter_card.dart';
import '../../../core/widgets/document_list_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../bloc/expense_list_bloc.dart';
import '../bloc/expense_list_event.dart';
import '../bloc/expense_list_state.dart';
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
    context.read<ExpenseListBloc>().add(const LoadExpenses());
  }

  Future<void> _selectDate(bool isStart, DateTime? current) async {
    final picked = await showThemedDatePicker(
      context,
      initialDate: current ?? DateTime.now(),
      color: AppTheme.errorRose,
    );
    if (picked != null && picked != current && mounted) {
      final bloc = context.read<ExpenseListBloc>();
      if (isStart) {
        bloc.add(
          SetExpenseDateFilter(
            startDate: picked,
            endDate: bloc.state.endDate,
          ),
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

  void _clearFilters() {
    context.read<ExpenseListBloc>().add(
      const SetExpenseDateFilter(startDate: null, endDate: null),
    );
  }

  Future<void> _openEditor({
    required bool readOnly,
    ExpenseEntry? expense,
  }) async {
    await ExpenseEditorPage.open(
      context,
      expense: expense,
      readOnly: readOnly,
    );
    if (mounted) {
      context.read<ExpenseListBloc>().add(const LoadExpenses());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Van Expenses'),
        actions: [
          IconButton(
            tooltip: 'Reload Expenses',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => context
                .read<ExpenseListBloc>()
                .add(const RefreshExpensesFromZoho()),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocConsumer<ExpenseListBloc, ExpenseListState>(
          listenWhen: (previous, current) =>
              previous.errorMessage != current.errorMessage ||
              previous.successMessage != current.successMessage,
          listener: (context, state) {
            if (state.errorMessage != null) {
              showErrorSnackBar(context, state.errorMessage!);
              context
                  .read<ExpenseListBloc>()
                  .add(const ClearExpenseListMessages());
            }
            if (state.successMessage != null) {
              showSuccessSnackBar(context, state.successMessage!);
              context
                  .read<ExpenseListBloc>()
                  .add(const ClearExpenseListMessages());
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
                  onClear: _clearFilters,
                  accentColor: AppTheme.errorRose,
                ),
                if (state.isLoading)
                  const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.errorRose,
                      ),
                    ),
                  )
                else if (list.isEmpty)
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async => context
                          .read<ExpenseListBloc>()
                          .add(const RefreshExpensesFromZoho()),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.6,
                            child: EmptyState(
                              icon: Icons.receipt_outlined,
                              title: 'No expenses found',
                              message: hasFilter
                                  ? 'Try expanding your date range filters.'
                                  : 'Click "+" below to log your first expense.',
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
                              .read<ExpenseListBloc>()
                              .add(const RefreshExpensesFromZoho()),
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
                              final expense = list[index];
                              final firstLine = expense.lines.isNotEmpty
                                  ? expense.lines.first
                                  : null;
                              final category = firstLine?.category ?? 'Expense';
                              final description = firstLine?.description ?? '';

                              return DocumentListCard(
                                key: ValueKey(expense.id),
                                docNumber: category,
                                customerName: description.isNotEmpty
                                    ? description
                                    : 'Van Expense',
                                date: _dateFormat.format(expense.date),
                                total: formatCurrency(expense.amount, cs),
                                isPendingSync: expense.isPendingSync,
                                accentColor: AppTheme.errorRose,
                                onTap: () => _openEditor(
                                  expense: expense,
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
        tooltip: 'Log New Expense',
        backgroundColor: AppTheme.errorRose,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(readOnly: false, expense: null),
        child: const Icon(Icons.add),
      ),
    );
  }
}
