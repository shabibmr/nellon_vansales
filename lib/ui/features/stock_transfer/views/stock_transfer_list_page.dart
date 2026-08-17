import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../domain/models/stock_transfer.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_picker.dart';
import '../../../core/utils/quantity_format.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/date_range_filter_card.dart';
import '../../../core/widgets/document_list_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../bloc/stock_transfer_list_bloc.dart';
import '../bloc/stock_transfer_list_event.dart';
import '../bloc/stock_transfer_list_state.dart';
import '../widgets/stock_transfer_status.dart';
import 'issue_to_van_page.dart';
import 'stock_unloading_page.dart';

/// Online-first list of Issue-to-Van or Stock-Unloading transfers.
///
/// Tapping a row opens that transfer for viewing/editing — editable while
/// Zoho still reports it as `draft`, read-only once processed.
class StockTransferListPage extends StatefulWidget {
  final StockTransferDirection direction;

  const StockTransferListPage({super.key, required this.direction});

  @override
  State<StockTransferListPage> createState() => _StockTransferListPageState();
}

class _StockTransferListPageState extends State<StockTransferListPage> {
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  bool get _isLoad => widget.direction == StockTransferDirection.load;

  String get _title => _isLoad ? 'Issue to Van' : 'Stock Unloading';

  Color get _accent =>
      _isLoad ? AppTheme.primaryIndigo : AppTheme.infoSky;

  @override
  void initState() {
    super.initState();
    context.read<StockTransferListBloc>().add(
      LoadStockTransfers(widget.direction),
    );
  }

  Future<void> _selectDate(bool isStart, DateTime? current) async {
    final picked = await showThemedDatePicker(
      context,
      initialDate: current ?? DateTime.now(),
      color: _accent,
    );
    if (picked != null && picked != current && mounted) {
      final bloc = context.read<StockTransferListBloc>();
      if (isStart) {
        bloc.add(
          SetStockTransferDateFilter(
            startDate: picked,
            endDate: bloc.state.endDate,
          ),
        );
      } else {
        bloc.add(
          SetStockTransferDateFilter(
            startDate: bloc.state.startDate,
            endDate: picked,
          ),
        );
      }
    }
  }

  void _clearFilters() {
    context.read<StockTransferListBloc>().add(
      const SetStockTransferDateFilter(startDate: null, endDate: null),
    );
  }

  Future<void> _openEditor() async {
    if (_isLoad) {
      await IssueToVanPage.open<void>(context);
    } else {
      await StockUnloadingPage.open<void>(context);
    }
    if (!mounted) return;
    context.read<StockTransferListBloc>().add(
      LoadStockTransfers(widget.direction),
    );
  }

  Future<void> _openTransfer(StockTransfer transfer) async {
    if (_isLoad) {
      await IssueToVanPage.open<void>(context, existing: transfer);
    } else {
      await StockUnloadingPage.open<void>(context, existing: transfer);
    }
    if (!mounted) return;
    context.read<StockTransferListBloc>().add(
      LoadStockTransfers(widget.direction),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: 'Reload $_title',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => context
                .read<StockTransferListBloc>()
                .add(const RefreshStockTransfersFromZoho()),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocConsumer<StockTransferListBloc, StockTransferListState>(
          listenWhen: (previous, current) =>
              previous.errorMessage != current.errorMessage ||
              previous.successMessage != current.successMessage,
          listener: (context, state) {
            if (state.errorMessage != null) {
              showErrorSnackBar(context, state.errorMessage!);
              context.read<StockTransferListBloc>().add(
                const ClearStockTransferListMessages(),
              );
            }
            if (state.successMessage != null) {
              showSuccessSnackBar(context, state.successMessage!);
              context.read<StockTransferListBloc>().add(
                const ClearStockTransferListMessages(),
              );
            }
          },
          builder: (context, state) {
            final hasFilter = state.startDate != null || state.endDate != null;
            final list = state.filteredTransfers;

            return Column(
              children: [
                DateRangeFilterCard(
                  startDate: state.startDate,
                  endDate: state.endDate,
                  onStartTap: () => _selectDate(true, state.startDate),
                  onEndTap: () => _selectDate(false, state.endDate),
                  onClear: _clearFilters,
                  accentColor: _accent,
                ),
                if (state.isLoading)
                  Expanded(
                    child: Center(
                      child: CircularProgressIndicator(color: _accent),
                    ),
                  )
                else if (list.isEmpty)
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async => context
                          .read<StockTransferListBloc>()
                          .add(const RefreshStockTransfersFromZoho()),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.6,
                            child: EmptyState(
                              icon: _isLoad
                                  ? Icons.local_shipping_outlined
                                  : Icons.unarchive_outlined,
                              title: _isLoad
                                  ? 'No Issue to Van transfers'
                                  : 'No Stock Unloading transfers',
                              message: hasFilter
                                  ? 'Try expanding your date range filters.'
                                  : 'Click "+" below to create your first transfer.',
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
                              .read<StockTransferListBloc>()
                              .add(const RefreshStockTransfersFromZoho()),
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
                              final transfer = list[index];
                              final qty = transfer.totalQuantity;
                              return DocumentListCard(
                                key: ValueKey(transfer.id),
                                docNumber: transfer.transferNumber.isNotEmpty
                                    ? transfer.transferNumber
                                    : transfer.id,
                                customerName: _title,
                                date: _dateFormat.format(transfer.date),
                                total: qty > 0
                                    ? formatQuantity(qty)
                                    : '—',
                                itemCount: transfer.lines.isEmpty
                                    ? null
                                    : transfer.lines.length,
                                isPendingSync: transfer.isPendingSync,
                                extraBadgeLabel: transfer.isPendingSync
                                    ? null
                                    : stockTransferStatusLabel(
                                        transfer.status,
                                      ),
                                extraBadgeColor: stockTransferStatusColor(
                                  transfer.status,
                                ),
                                accentColor: _accent,
                                onTap: () => _openTransfer(transfer),
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
        tooltip: _isLoad ? 'New Issue to Van' : 'New Stock Unloading',
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        onPressed: _openEditor,
        child: const Icon(Icons.add),
      ),
    );
  }
}
