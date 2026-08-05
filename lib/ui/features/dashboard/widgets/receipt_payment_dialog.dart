import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../data/services/document_number_service.dart';
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

const _paymentModes = ['Cash', 'Cheque', 'Bank Transfer', 'Card'];

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
      create: (ctx) => ReceiptAllocationBloc(
        salesRepository: ctx.read<SalesRepository>(),
        syncWorker: sl<SyncWorker>(),
        documentNumberService: sl<DocumentNumberService>(),
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
  State<_ReceiptPaymentDialogView> createState() =>
      _ReceiptPaymentDialogViewState();
}

class _ReceiptPaymentDialogViewState extends State<_ReceiptPaymentDialogView> {
  final _amountController = TextEditingController();
  final Map<String, TextEditingController> _allocationControllers = {};
  final Map<String, FocusNode> _allocationFocusNodes = {};

  /// When true, allocation [TextEditingController] updates must not dispatch
  /// [InvoiceAllocationEdited] (avoids FIFO → text sync → onChanged loops).
  bool _syncingControllers = false;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_onAmountChanged);
  }

  void _onAmountChanged() {
    if (!mounted) return;
    context.read<ReceiptAllocationBloc>().add(
      PaymentAmountChanged(_amountController.text),
    );
  }

  void _setControllerText(TextEditingController ctrl, String text) {
    if (ctrl.text == text) return;
    _syncingControllers = true;
    ctrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _syncingControllers = false;
  }

  String _normalizedPaymentMode(String mode) =>
      _paymentModes.contains(mode) ? mode : _paymentModes.first;

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
    final theme = Theme.of(context);
    // Glass / transparent themes make AlertDialog surfaces disappear; pin a real fill.
    final surface = theme.colorScheme.surface;
    final solidBg = surface.a == 0
        ? (theme.brightness == Brightness.dark
              ? AppTheme.darkSurface
              : AppTheme.lightSurface)
        : surface;

    return BlocListener<ReceiptAllocationBloc, ReceiptAllocationState>(
      listenWhen: (prev, curr) =>
          prev.submitSuccess != curr.submitSuccess ||
          prev.submitError != curr.submitError ||
          prev.allocations != curr.allocations ||
          prev.openInvoices != curr.openInvoices ||
          prev.paymentAmount != curr.paymentAmount,
      listener: (context, state) {
        if (state.submitSuccess) {
          Navigator.pop(context);
          showSuccessSnackBar(
            context,
            'Payment Voucher for ${formatCurrency(state.paymentAmount, cs)} queued offline!',
          );
          widget.onPaymentLogged();
          return;
        }
        if (state.submitError != null) {
          showErrorSnackBar(context, state.submitError!);
        }

        // Focus-aware sync of allocation controllers (never cascade into bloc).
        for (final inv in state.openInvoices) {
          PaymentAllocation? alloc;
          for (final a in state.allocations) {
            if (a.invoiceId == inv.invoiceId) {
              alloc = a;
              break;
            }
          }
          final amountApplied = alloc?.amountApplied ?? 0.0;
          final ctrl = _allocationControllers.putIfAbsent(
            inv.invoiceId,
            () => TextEditingController(),
          );
          final focusNode = _allocationFocusNodes.putIfAbsent(
            inv.invoiceId,
            () => FocusNode(),
          );

          final expectedText = amountApplied > 0
              ? amountApplied.toStringAsFixed(2)
              : '';
          if (ctrl.text != expectedText && !focusNode.hasFocus) {
            _setControllerText(ctrl, expectedText);
          }
        }
      },
      // Keep AlertDialog shell stable — only inner sections rebuild on amount/FIFO.
      child: AlertDialog(
        backgroundColor: solidBg,
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
              // Amount field lives outside allocation BlocBuilders so typing
              // does not recreate this TextFormField every keystroke.
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

              BlocBuilder<ReceiptAllocationBloc, ReceiptAllocationState>(
                buildWhen: (p, c) => p.paymentMode != c.paymentMode,
                builder: (context, state) {
                  final mode = _normalizedPaymentMode(state.paymentMode);
                  return DropdownButtonFormField<String>(
                    key: ValueKey('payment_mode_$mode'),
                    initialValue: mode,
                    decoration: const InputDecoration(
                      labelText: 'Payment Mode',
                    ),
                    items: _paymentModes
                        .map(
                          (m) => DropdownMenuItem(value: m, child: Text(m)),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        context.read<ReceiptAllocationBloc>().add(
                          PaymentModeChanged(val),
                        );
                      }
                    },
                  );
                },
              ),

              BlocBuilder<ReceiptAllocationBloc, ReceiptAllocationState>(
                buildWhen: (p, c) =>
                    p.openInvoices != c.openInvoices ||
                    p.allocations != c.allocations ||
                    p.paymentAmount != c.paymentAmount,
                builder: (context, state) {
                  if (state.openInvoices.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  final totalAllocated = state.totalAllocated;
                  final paymentAmount = state.paymentAmount;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'INVOICE ALLOCATIONS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Flexible(
                            child: Text(
                              'Allocated: $cs${totalAllocated.toStringAsFixed(2)} / $cs${paymentAmount.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: totalAllocated > paymentAmount + 0.005
                                    ? AppTheme.errorRose
                                    : AppTheme.successEmerald,
                              ),
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...state.openInvoices.map((inv) {
                        final ctrl = _allocationControllers.putIfAbsent(
                          inv.invoiceId,
                          () => TextEditingController(),
                        );
                        final focusNode = _allocationFocusNodes.putIfAbsent(
                          inv.invoiceId,
                          () => FocusNode(),
                        );
                        PaymentAllocation? alloc;
                        for (final a in state.allocations) {
                          if (a.invoiceId == inv.invoiceId) {
                            alloc = a;
                            break;
                          }
                        }
                        final amountApplied = alloc?.amountApplied ?? 0.0;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
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
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(fontSize: 12),
                                    decoration: InputDecoration(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 4,
                                          ),
                                      prefixText: cs,
                                      hintText: '0.00',
                                      errorText: amountApplied > inv.balance
                                          ? 'Too high'
                                          : null,
                                      errorMaxLines: 1,
                                      isDense: true,
                                    ),
                                    onChanged: (v) {
                                      if (_syncingControllers) return;
                                      context
                                          .read<ReceiptAllocationBloc>()
                                          .add(
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
                      }),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          BlocBuilder<ReceiptAllocationBloc, ReceiptAllocationState>(
            buildWhen: (p, c) =>
                p.submitting != c.submitting ||
                p.paymentAmount != c.paymentAmount ||
                p.allocations != c.allocations ||
                p.openInvoices != c.openInvoices,
            builder: (context, state) {
              final submitting = state.submitting;
              return Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: submitting
                        ? null
                        : () => Navigator.pop(context),
                    child: const Text('CANCEL'),
                  ),
                  const SizedBox(width: 8),
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
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('LOG RECEIPT'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
