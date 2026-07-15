import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../data/services/sync_worker.dart';
import '../../../../data/services/injection.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../../ui/core/utils/currency.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../bloc/receipt_allocation_bloc.dart';
import '../bloc/receipt_allocation_event.dart';
import '../bloc/receipt_allocation_state.dart';

/// Modal dialog for logging a [ReceiptVoucher] payment collection.
///
/// Prompts the field for the payment amount and permits choosing the payment mode
/// (Cash, Cheque, Bank Transfer, Card). Updates the customer's outstanding balance
/// instantly in the local Hive cache, and enqueues a sync job to post the payment to Zoho Books.
class ReceiptPaymentDialog extends StatelessWidget {
  /// The selected customer profile paying their invoice.
  final Customer customer;

  /// Callback triggered when the payment collection is successfully registered and cached.
  final VoidCallback onPaymentLogged;

  /// Creates a new [ReceiptPaymentDialog] widget.
  const ReceiptPaymentDialog({
    super.key,
    required this.customer,
    required this.onPaymentLogged,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ReceiptAllocationBloc>(
      create: (_) => ReceiptAllocationBloc(
        salesRepository: sl<SalesRepository>(),
        syncWorker: sl<SyncWorker>(),
      )..add(ReceiptAllocationStarted(customer)),
      child: _ReceiptPaymentDialogView(
        customer: customer,
        onPaymentLogged: onPaymentLogged,
      ),
    );
  }
}

class _ReceiptPaymentDialogView extends StatefulWidget {
  final Customer customer;
  final VoidCallback onPaymentLogged;

  const _ReceiptPaymentDialogView({
    required this.customer,
    required this.onPaymentLogged,
  });

  @override
  State<_ReceiptPaymentDialogView> createState() => _ReceiptPaymentDialogViewState();
}

class _ReceiptPaymentDialogViewState extends State<_ReceiptPaymentDialogView> {
  final _amountController = TextEditingController();
  final Map<String, TextEditingController> _allocationControllers = {};
  final Map<String, FocusNode> _allocationFocusNodes = {};

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_onAmountChanged);
  }

  void _onAmountChanged() {
    context.read<ReceiptAllocationBloc>().add(
      PaymentAmountChanged(_amountController.text),
    );
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    for (final ctrl in _allocationControllers.values) {
      ctrl.dispose();
    }
    for (final node in _allocationFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;

    return BlocListener<ReceiptAllocationBloc, ReceiptAllocationState>(
      listener: (context, state) {
        if (state.submitSuccess) {
          Navigator.pop(context);
          showSuccessSnackBar(
            context,
            'Payment Voucher for ${formatCurrency(state.paymentAmount, cs)} queued offline!',
          );
          widget.onPaymentLogged();
        } else if (state.submitError != null) {
          showErrorSnackBar(context, state.submitError!);
        }

        // Focus-aware sync of allocation controllers text
        for (final inv in state.openInvoices) {
          final alloc = state.allocations.firstWhere(
            (a) => a.invoiceId == inv.invoiceId,
            orElse: () => PaymentAllocation(
              invoiceId: inv.invoiceId,
              invoiceNumber: inv.invoiceNumber,
              amountApplied: 0.0,
            ),
          );
          final ctrl = _allocationControllers.putIfAbsent(
            inv.invoiceId,
            () => TextEditingController(),
          );
          final focusNode = _allocationFocusNodes.putIfAbsent(
            inv.invoiceId,
            () => FocusNode(),
          );

          final hasFocus = focusNode.hasFocus;
          final expectedText = alloc.amountApplied > 0
              ? alloc.amountApplied.toStringAsFixed(2)
              : '';
          if (ctrl.text != expectedText && !hasFocus) {
            ctrl.text = expectedText;
          }
        }
      },
      child: BlocBuilder<ReceiptAllocationBloc, ReceiptAllocationState>(
        builder: (context, state) {
          final totalAllocated = state.totalAllocated;
          final paymentAmount = state.paymentAmount;
          final submitting = state.submitting;

          return AlertDialog(
            title: Text('Receipt Payment: ${widget.customer.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Log customer payment towards their outstanding balances directly into Zoho Books.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Payment Amount ($cs)',
                      prefixIcon: const Icon(
                        Icons.currency_rupee,
                        color: AppTheme.primaryIndigo,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Dropdown for payment modes
                  DropdownButtonFormField<String>(
                    initialValue: state.paymentMode,
                    decoration: const InputDecoration(labelText: 'Payment Mode'),
                    items: ['Cash', 'Cheque', 'Bank Transfer', 'Card']
                        .map(
                          (mode) => DropdownMenuItem(value: mode, child: Text(mode)),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        context.read<ReceiptAllocationBloc>().add(
                          PaymentModeChanged(val),
                        );
                      }
                    },
                  ),

                  if (state.openInvoices.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'INVOICE ALLOCATIONS',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Allocated: $cs${totalAllocated.toStringAsFixed(2)} / $cs${paymentAmount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: totalAllocated > paymentAmount + 0.005
                                ? AppTheme.errorRose
                                : AppTheme.successEmerald,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: state.openInvoices.length,
                      itemBuilder: (context, index) {
                        final inv = state.openInvoices[index];
                        final ctrl = _allocationControllers.putIfAbsent(
                          inv.invoiceId,
                          () => TextEditingController(),
                        );
                        final focusNode = _allocationFocusNodes.putIfAbsent(
                          inv.invoiceId,
                          () => FocusNode(),
                        );
                        final alloc = state.allocations.firstWhere(
                          (a) => a.invoiceId == inv.invoiceId,
                          orElse: () => PaymentAllocation(
                            invoiceId: inv.invoiceId,
                            invoiceNumber: inv.invoiceNumber,
                            amountApplied: 0.0,
                          ),
                        );

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        inv.invoiceNumber,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        'Outstanding: $cs${inv.balance.toStringAsFixed(2)}',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 100,
                                  child: TextFormField(
                                    controller: ctrl,
                                    focusNode: focusNode,
                                    keyboardType: const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(fontSize: 12),
                                    decoration: InputDecoration(
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 4,
                                      ),
                                      prefixText: cs,
                                      hintText: '0.00',
                                      errorText: alloc.amountApplied > inv.balance
                                          ? 'Too high'
                                          : null,
                                    ),
                                    onChanged: (v) {
                                      context.read<ReceiptAllocationBloc>().add(
                                        InvoiceAllocationEdited(
                                          invoiceId: inv.invoiceId,
                                          invoiceNumber: inv.invoiceNumber,
                                          value: v,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.pop(context),
                child: const Text('CANCEL'),
              ),
              ElevatedButton(
                onPressed: !state.canSubmit || submitting
                    ? null
                    : () => context.read<ReceiptAllocationBloc>().add(
                          ReceiptSubmitted(),
                        ),
                child: submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('LOG RECEIPT'),
              ),
            ],
          );
        },
      ),
    );
  }
}
