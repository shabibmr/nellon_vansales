import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/models/open_invoice.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../cubit/receipt_allocations_sheet_cubit.dart';

/// Bottom sheet that lets the user pick which open invoices a receipt settles
/// and how much goes to each (partial amounts allowed).
///
/// Returns the new allocation list on APPLY, or `null` if dismissed.
Future<List<PaymentAllocation>?> showReceiptAllocationsSheet(
  BuildContext context, {
  required List<OpenInvoice> openInvoices,
  required List<PaymentAllocation> allocations,
  required double paymentAmount,
  required String currencySymbol,
}) {
  return showModalBottomSheet<List<PaymentAllocation>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => BlocProvider(
      create: (_) => ReceiptAllocationsSheetCubit(
        openInvoices: openInvoices,
        allocations: allocations,
        paymentAmount: paymentAmount,
      ),
      child: _ReceiptAllocationsSheet(currencySymbol: currencySymbol),
    ),
  );
}

class _ReceiptAllocationsSheet extends StatefulWidget {
  final String currencySymbol;

  const _ReceiptAllocationsSheet({required this.currencySymbol});

  @override
  State<_ReceiptAllocationsSheet> createState() =>
      _ReceiptAllocationsSheetState();
}

class _ReceiptAllocationsSheetState extends State<_ReceiptAllocationsSheet> {
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    final initial = context.read<ReceiptAllocationsSheetCubit>().state;
    _controllers = {
      for (final inv in initial.invoices)
        inv.invoiceId: TextEditingController(
          text: initial.amountFor(inv.invoiceId) > 0
              ? initial.amountFor(inv.invoiceId).toStringAsFixed(2)
              : '',
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Pushes cubit-driven changes (e.g. fill-remaining) into the text fields
  /// without disturbing a field the user is mid-typing in.
  void _syncControllers(ReceiptAllocationsSheetState state) {
    for (final inv in state.invoices) {
      final ctrl = _controllers[inv.invoiceId]!;
      final typed = double.tryParse(ctrl.text) ?? 0.0;
      final target = state.amountFor(inv.invoiceId);
      if ((typed - target).abs() > 0.0001) {
        ctrl.text = target > 0 ? target.toStringAsFixed(2) : '';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.currencySymbol;

    return BlocConsumer<ReceiptAllocationsSheetCubit,
        ReceiptAllocationsSheetState>(
      listener: (_, state) => _syncControllers(state),
      builder: (context, state) {
        final cubit = context.read<ReceiptAllocationsSheetCubit>();

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'ALLOCATE TO INVOICES',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        'Allocated: ${formatCurrency(state.totalAllocated, cs)}'
                        ' / ${formatCurrency(state.paymentAmount, cs)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: state.isOverPayment
                              ? AppTheme.errorRose
                              : AppTheme.successEmerald,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: state.invoices.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No open invoices for this customer.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: state.invoices.length,
                        itemBuilder: (context, i) {
                          final inv = state.invoices[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          inv.invoiceNumber,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          'Outstanding: '
                                          '${formatCurrency(inv.balance, cs)}',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 110,
                                    child: TextField(
                                      controller: _controllers[inv.invoiceId],
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(fontSize: 12),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        prefixText: cs,
                                        hintText: '0.00',
                                        errorText: state.isInvoiceOverflow(inv)
                                            ? 'Too high'
                                            : null,
                                        suffixIcon: IconButton(
                                          iconSize: 16,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          tooltip: 'Fill remaining',
                                          icon: const Icon(Icons.bolt),
                                          onPressed: () =>
                                              cubit.fillRemaining(inv.invoiceId),
                                        ),
                                      ),
                                      onChanged: (v) =>
                                          cubit.setAmount(inv.invoiceId, v),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('CANCEL'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: state.canApply
                            ? () => Navigator.of(
                                context,
                              ).pop(state.toAllocations())
                            : null,
                        child: const Text('APPLY'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
