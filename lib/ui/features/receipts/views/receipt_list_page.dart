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
    final picked = await showThemedDatePicker(
      context,
      initialDate: current,
      color: AppTheme.successEmerald,
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
    final cs = context.org.currencySymbol;

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
            showErrorSnackBar(context, state.errorMessage!);
            context.read<ReceiptBloc>().add(ClearReceiptMessages());
          }
          if (state.successMessage != null) {
            showSuccessSnackBar(context, state.successMessage!);
            context.read<ReceiptBloc>().add(ClearReceiptMessages());
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
                onClear: hasFilter
                    ? () => context.read<ReceiptBloc>().add(const SetReceiptDateFilter())
                    : null,
                accentColor: AppTheme.successEmerald,
              ),

              if (state.isLoading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: AppTheme.successEmerald),
                  ),
                )
              else if (list.isEmpty)
                Expanded(
                  child: EmptyState(
                    icon: Icons.payments_outlined,
                    title: 'No receipts found',
                    message: hasFilter
                        ? 'Try expanding your date range.'
                        : 'Tap "+" to log a new payment receipt.',
                  ),
                )
              else
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: ListView.separated(
                        padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 80),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final receipt = list[index];
                          return DocumentListCard(
                            docNumber: receipt.paymentNumber,
                            customerName: receipt.customerName,
                            date: _dateFormat.format(receipt.date),
                            subtitle: '${receipt.paymentMode}  •  ${_dateFormat.format(receipt.date)}',
                            total: formatCurrency(receipt.amount, cs),
                            isPendingSync: receipt.isPendingSync,
                            accentColor: AppTheme.successEmerald,
                            onTap: () {
                              context.read<ReceiptBloc>().add(StartEditReceipt(receipt));
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ReceiptEditorPage()),
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
