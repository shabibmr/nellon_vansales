import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../domain/models/receipt_voucher.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/date_picker.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/date_range_filter_card.dart';
import '../../../core/widgets/document_list_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../bloc/receipt_list_bloc.dart';
import '../bloc/receipt_list_event.dart';
import '../bloc/receipt_list_state.dart';
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
    context.read<ReceiptListBloc>().add(const LoadReceipts());
  }

  Future<void> _selectDate(bool isStart, DateTime? current) async {
    final picked = await showThemedDatePicker(
      context,
      initialDate: current ?? DateTime.now(),
      color: AppTheme.successEmerald,
    );
    if (picked != null && picked != current && mounted) {
      final bloc = context.read<ReceiptListBloc>();
      if (isStart) {
        bloc.add(
          SetReceiptDateFilter(
            startDate: picked,
            endDate: bloc.state.endDate,
          ),
        );
      } else {
        bloc.add(
          SetReceiptDateFilter(
            startDate: bloc.state.startDate,
            endDate: picked,
          ),
        );
      }
    }
  }

  void _clearFilters() {
    context.read<ReceiptListBloc>().add(
      const SetReceiptDateFilter(startDate: null, endDate: null),
    );
  }

  Future<void> _openEditor({
    required bool readOnly,
    ReceiptVoucher? receipt,
  }) async {
    await ReceiptEditorPage.open(
      context,
      receipt: receipt,
      readOnly: readOnly,
    );
    if (mounted) {
      context.read<ReceiptListBloc>().add(const LoadReceipts());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt Vouchers'),
        actions: [
          IconButton(
            tooltip: 'Reload Receipts',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => context
                .read<ReceiptListBloc>()
                .add(const RefreshReceiptsFromZoho()),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocConsumer<ReceiptListBloc, ReceiptListState>(
          listenWhen: (previous, current) =>
              previous.errorMessage != current.errorMessage ||
              previous.successMessage != current.successMessage,
          listener: (context, state) {
            if (state.errorMessage != null) {
              showErrorSnackBar(context, state.errorMessage!);
              context
                  .read<ReceiptListBloc>()
                  .add(const ClearReceiptListMessages());
            }
            if (state.successMessage != null) {
              showSuccessSnackBar(context, state.successMessage!);
              context
                  .read<ReceiptListBloc>()
                  .add(const ClearReceiptListMessages());
            }
          },
          builder: (context, state) {
            final hasFilter = state.startDate != null || state.endDate != null;
            final list = state.filteredReceipts;

            return Column(
              children: [
                DateRangeFilterCard(
                  startDate: state.startDate,
                  endDate: state.endDate,
                  onStartTap: () => _selectDate(true, state.startDate),
                  onEndTap: () => _selectDate(false, state.endDate),
                  onClear: _clearFilters,
                  accentColor: AppTheme.successEmerald,
                ),
                if (state.isLoading)
                  const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.successEmerald,
                      ),
                    ),
                  )
                else if (list.isEmpty)
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async => context
                          .read<ReceiptListBloc>()
                          .add(const RefreshReceiptsFromZoho()),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.6,
                            child: EmptyState(
                              icon: Icons.payments_outlined,
                              title: 'No receipts found',
                              message: hasFilter
                                  ? 'Try expanding your date range filters.'
                                  : 'Click "+" below to log a new receipt.',
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
                              .read<ReceiptListBloc>()
                              .add(const RefreshReceiptsFromZoho()),
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
                              final receipt = list[index];
                              return DocumentListCard(
                                key: ValueKey(receipt.id),
                                docNumber: receipt.paymentNumber,
                                customerName: receipt.customerName,
                                date: _dateFormat.format(receipt.date),
                                subtitle:
                                    '${receipt.paymentMode}  •  ${_dateFormat.format(receipt.date)}',
                                total: formatCurrency(receipt.amount, cs),
                                isPendingSync: receipt.isPendingSync,
                                accentColor: AppTheme.successEmerald,
                                onTap: () => _openEditor(
                                  receipt: receipt,
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
        tooltip: 'Log New Receipt',
        backgroundColor: AppTheme.successEmerald,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(readOnly: false, receipt: null),
        child: const Icon(Icons.add),
      ),
    );
  }
}
