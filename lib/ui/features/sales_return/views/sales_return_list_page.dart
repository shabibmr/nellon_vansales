import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/utils/date_picker.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../../ui/core/utils/currency.dart';
import '../../../../ui/core/widgets/date_range_filter_card.dart';
import '../../../../ui/core/widgets/document_list_card.dart';
import '../../../../ui/core/widgets/empty_state.dart';
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
    final picked = await showThemedDatePicker(
      context,
      initialDate: current,
      color: AppTheme.warningAmber,
    );
    if (picked != null && mounted) {
      final bloc = context.read<SalesReturnBloc>();
      if (isStart) {
        bloc.add(
          SetReturnDateFilter(startDate: picked, endDate: bloc.state.endDate),
        );
      } else {
        bloc.add(
          SetReturnDateFilter(startDate: bloc.state.startDate, endDate: picked),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
      body: SafeArea(
        child: BlocConsumer<SalesReturnBloc, SalesReturnState>(
        listener: (context, state) {
          if (state.errorMessage != null) {
            showErrorSnackBar(context, state.errorMessage!);
            context.read<SalesReturnBloc>().add(ClearReturnMessages());
          }
          if (state.successMessage != null) {
            showSuccessSnackBar(context, state.successMessage!);
            context.read<SalesReturnBloc>().add(ClearReturnMessages());
          }
        },
        builder: (context, state) {
          final hasFilter = state.startDate != null || state.endDate != null;
          final list = state.filteredReturns;

          return Column(
            children: [
              DateRangeFilterCard(
                startDate: state.startDate,
                endDate: state.endDate,
                onStartTap: () => _selectDate(true, state.startDate),
                onEndTap: () => _selectDate(false, state.endDate),
                onClear: hasFilter
                    ? () => context.read<SalesReturnBloc>().add(
                        const SetReturnDateFilter(
                          startDate: null,
                          endDate: null,
                        ),
                      )
                    : null,
                accentColor: AppTheme.warningAmber,
              ),

              if (state.isLoading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.warningAmber,
                    ),
                  ),
                )
              else if (list.isEmpty)
                Expanded(
                  child: EmptyState(
                    icon: Icons.assignment_return_outlined,
                    title: 'No returns found',
                    message: hasFilter
                        ? 'Try expanding your date range filters.'
                        : 'Tap "+" to log a sales return.',
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
                          bottom: 80,
                          top: 8,
                        ),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final ret = list[index];
                          final dateStr = _dateFormat.format(ret.date);
                          final subtitle = ret.reason.isNotEmpty
                              ? 'Date: $dateStr  •  ${ret.reason}'
                              : 'Date: $dateStr';
                          return DocumentListCard(
                            docNumber: ret.creditNoteNumber,
                            customerName: ret.customerName,
                            date: dateStr,
                            subtitle: subtitle,
                            total: formatCurrency(ret.total, cs),
                            itemCount: ret.items.length,
                            isPendingSync: ret.isPendingSync,
                            accentColor: AppTheme.warningAmber,
                            onTap: () {
                              context.read<SalesReturnBloc>().add(
                                StartEditReturn(ret),
                              );
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SalesReturnEditorPage(),
                                ),
                              );
                            },
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
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Create New Sales Return',
        backgroundColor: AppTheme.warningAmber,
        foregroundColor: Colors.white,
        onPressed: () {
          context.read<SalesReturnBloc>().add(StartNewReturn());
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SalesReturnEditorPage()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
