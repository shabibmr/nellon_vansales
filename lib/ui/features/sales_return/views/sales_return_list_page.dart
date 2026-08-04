import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../domain/models/sales_return.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/date_picker.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/date_range_filter_card.dart';
import '../../../core/widgets/document_list_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../bloc/sales_return_list_bloc.dart';
import '../bloc/sales_return_list_event.dart';
import '../bloc/sales_return_list_state.dart';
import 'sales_return_editor_page.dart';

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
    context.read<SalesReturnListBloc>().add(const LoadReturns());
  }

  Future<void> _selectDate(bool isStart, DateTime? current) async {
    final picked = await showThemedDatePicker(
      context,
      initialDate: current ?? DateTime.now(),
      color: AppTheme.warningAmber,
    );
    if (picked != null && picked != current && mounted) {
      final bloc = context.read<SalesReturnListBloc>();
      if (isStart) {
        bloc.add(
          SetReturnDateFilter(
            startDate: picked,
            endDate: bloc.state.endDate,
          ),
        );
      } else {
        bloc.add(
          SetReturnDateFilter(
            startDate: bloc.state.startDate,
            endDate: picked,
          ),
        );
      }
    }
  }

  void _clearFilters() {
    context.read<SalesReturnListBloc>().add(
      const SetReturnDateFilter(startDate: null, endDate: null),
    );
  }

  Future<void> _openEditor({
    required bool readOnly,
    SalesReturn? salesReturn,
  }) async {
    await SalesReturnEditorPage.open(
      context,
      salesReturn: salesReturn,
      readOnly: readOnly,
    );
    if (mounted) {
      context.read<SalesReturnListBloc>().add(const LoadReturns());
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
            onPressed: () => context
                .read<SalesReturnListBloc>()
                .add(const RefreshReturnsFromZoho()),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocConsumer<SalesReturnListBloc, SalesReturnListState>(
          listenWhen: (previous, current) =>
              previous.errorMessage != current.errorMessage ||
              previous.successMessage != current.successMessage,
          listener: (context, state) {
            if (state.errorMessage != null) {
              showErrorSnackBar(context, state.errorMessage!);
              context
                  .read<SalesReturnListBloc>()
                  .add(const ClearReturnListMessages());
            }
            if (state.successMessage != null) {
              showSuccessSnackBar(context, state.successMessage!);
              context
                  .read<SalesReturnListBloc>()
                  .add(const ClearReturnListMessages());
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
                  onClear: _clearFilters,
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
                    child: RefreshIndicator(
                      onRefresh: () async => context
                          .read<SalesReturnListBloc>()
                          .add(const RefreshReturnsFromZoho()),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.6,
                            child: EmptyState(
                              icon: Icons.assignment_return_outlined,
                              title: 'No returns found',
                              message: hasFilter
                                  ? 'Try expanding your date range filters.'
                                  : 'Click "+" below to log a sales return.',
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
                              .read<SalesReturnListBloc>()
                              .add(const RefreshReturnsFromZoho()),
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
                              final ret = list[index];
                              final dateStr = _dateFormat.format(ret.date);
                              final subtitle = ret.reason.isNotEmpty
                                  ? 'Date: $dateStr  •  ${ret.reason}'
                                  : 'Date: $dateStr';
                              return DocumentListCard(
                                key: ValueKey(ret.id),
                                docNumber: ret.creditNoteNumber,
                                customerName: ret.customerName,
                                date: dateStr,
                                subtitle: subtitle,
                                total: formatCurrency(ret.total, cs),
                                itemCount: ret.items.length,
                                isPendingSync: ret.isPendingSync,
                                accentColor: AppTheme.warningAmber,
                                onTap: () => _openEditor(
                                  salesReturn: ret,
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
        tooltip: 'Create New Sales Return',
        backgroundColor: AppTheme.warningAmber,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(readOnly: false, salesReturn: null),
        child: const Icon(Icons.add),
      ),
    );
  }
}
