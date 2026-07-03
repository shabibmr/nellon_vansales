import 'package:flutter/material.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../domain/models/open_invoice.dart';
import '../../../../data/models/receipt_voucher_model.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/sync_worker.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../../ui/core/utils/currency.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';

/// Modal dialog for logging a [ReceiptVoucher] payment collection.
///
/// Prompts the field for the payment amount and permits choosing the payment mode
/// (Cash, Cheque, Bank Transfer, Card). Updates the customer's outstanding balance
/// instantly in the local Hive cache, and enqueues a sync job to post the payment to Zoho Books.
class ReceiptPaymentDialog extends StatefulWidget {
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
  State<ReceiptPaymentDialog> createState() => _ReceiptPaymentDialogState();
}

class _ReceiptPaymentDialogState extends State<ReceiptPaymentDialog> {
  final _amountController = TextEditingController();
  String _paymentMode = 'Cash';
  final HiveDatabaseService _db = sl<HiveDatabaseService>();
  final Map<String, TextEditingController> _allocationControllers = {};
  final Map<String, FocusNode> _allocationFocusNodes = {};
  List<PaymentAllocation> _allocations = [];
  late final List<OpenInvoice> _openInvoices;

  @override
  void initState() {
    super.initState();
    _openInvoices = _db.getOpenInvoices(customerId: widget.customer.id)
      ..sort((a, b) => a.date.compareTo(b.date));
    _amountController.addListener(_onAmountChanged);
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

  void _onAmountChanged() {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final list = <PaymentAllocation>[];
    double remainingAmount = amount;

    for (final invoice in _openInvoices) {
      if (remainingAmount <= 0) break;
      final balance = invoice.balance;
      if (balance <= 0) continue;

      final allocated = remainingAmount >= balance ? balance : remainingAmount;
      list.add(
        PaymentAllocation(
          invoiceId: invoice.invoiceId,
          invoiceNumber: invoice.invoiceNumber,
          amountApplied: double.parse(allocated.toStringAsFixed(2)),
        ),
      );
      remainingAmount -= allocated;
      remainingAmount = double.parse(remainingAmount.toStringAsFixed(2));
    }

    setState(() {
      _allocations = list;
      // Sync allocation controllers text
      for (final inv in _openInvoices) {
        final alloc = _allocations.firstWhere(
          (a) => a.invoiceId == inv.invoiceId,
          orElse: () => PaymentAllocation(
            invoiceId: inv.invoiceId,
            invoiceNumber: inv.invoiceNumber,
            amountApplied: 0.0,
          ),
        );
        final ctrl = _allocationControllers[inv.invoiceId];
        final hasFocus =
            _allocationFocusNodes[inv.invoiceId]?.hasFocus ?? false;
        final expectedText = alloc.amountApplied > 0
            ? alloc.amountApplied.toStringAsFixed(2)
            : '';
        if (ctrl != null) {
          if (ctrl.text != expectedText && !hasFocus) {
            ctrl.text = expectedText;
          }
        } else {
          _allocationControllers[inv.invoiceId] = TextEditingController(
            text: expectedText,
          );
        }
      }
    });
  }

  void _onAllocationChanged(
    String invoiceId,
    String invoiceNumber,
    String value,
  ) {
    final parsed = double.tryParse(value) ?? 0.0;
    setState(() {
      final index = _allocations.indexWhere((a) => a.invoiceId == invoiceId);
      if (index >= 0) {
        if (parsed <= 0) {
          _allocations.removeAt(index);
        } else {
          _allocations[index] = PaymentAllocation(
            invoiceId: invoiceId,
            invoiceNumber: invoiceNumber,
            amountApplied: parsed,
          );
        }
      } else if (parsed > 0) {
        _allocations.add(
          PaymentAllocation(
            invoiceId: invoiceId,
            invoiceNumber: invoiceNumber,
            amountApplied: parsed,
          ),
        );
      }
    });
  }

  bool _isFormValid() {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amount <= 0) return false;

    double totalAllocated = 0.0;
    for (final alloc in _allocations) {
      if (alloc.amountApplied < 0) return false;
      final inv = _openInvoices.firstWhere(
        (i) => i.invoiceId == alloc.invoiceId,
        orElse: () => OpenInvoice(
          invoiceId: '',
          invoiceNumber: '',
          customerId: '',
          date: DateTime.now(),
          dueDate: DateTime.now(),
          total: 0.0,
          balance: 0.0,
          status: '',
        ),
      );
      if (inv.invoiceId.isEmpty || alloc.amountApplied > inv.balance)
        return false;
      totalAllocated += alloc.amountApplied;
    }
    if (double.parse(totalAllocated.toStringAsFixed(2)) >
        double.parse(amount.toStringAsFixed(2))) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;
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
              initialValue: _paymentMode,
              decoration: const InputDecoration(labelText: 'Payment Mode'),
              items: ['Cash', 'Cheque', 'Bank Transfer', 'Card']
                  .map(
                    (mode) => DropdownMenuItem(value: mode, child: Text(mode)),
                  )
                  .toList(),
              onChanged: (val) {
                setState(() {
                  _paymentMode = val ?? 'Cash';
                });
              },
            ),

            if (_openInvoices.isNotEmpty) ...[
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
                  Builder(
                    builder: (context) {
                      final amount =
                          double.tryParse(_amountController.text.trim()) ?? 0.0;
                      final totalAllocated = _allocations.fold(
                        0.0,
                        (sum, a) => sum + a.amountApplied,
                      );
                      return Text(
                        'Allocated: $cs${totalAllocated.toStringAsFixed(2)} / $cs${amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: totalAllocated > amount + 0.005
                              ? AppTheme.errorRose
                              : AppTheme.successEmerald,
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _openInvoices.length,
                itemBuilder: (context, index) {
                  final inv = _openInvoices[index];
                  final ctrl = _allocationControllers.putIfAbsent(
                    inv.invoiceId,
                    () => TextEditingController(),
                  );
                  final focusNode = _allocationFocusNodes.putIfAbsent(
                    inv.invoiceId,
                    () => FocusNode(),
                  );
                  final alloc = _allocations.firstWhere(
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
                              keyboardType:
                                  const TextInputType.numberWithOptions(
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
                                _onAllocationChanged(
                                  inv.invoiceId,
                                  inv.invoiceNumber,
                                  v,
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
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: !_isFormValid()
              ? null
              : () async {
                  final amount =
                      double.tryParse(_amountController.text.trim()) ?? 0.0;
                  if (amount <= 0) return;

                  final tempId =
                      'temp_pay_${DateTime.now().millisecondsSinceEpoch}';
                  final voucher = ReceiptVoucher(
                    id: tempId,
                    paymentNumber:
                        'PAY-TEMP-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
                    customerId: widget.customer.id,
                    customerName: widget.customer.name,
                    allocations: _allocations,
                    amount: amount,
                    paymentMode: _paymentMode,
                    referenceNumber:
                        'REF-VAN-${DateTime.now().millisecondsSinceEpoch.toString().substring(10)}',
                    date: DateTime.now(),
                    isPendingSync: true,
                  );

                  // Local Cache update (deducts Customer outstanding balance instantly!)
                  await _db.saveLocalReceipt(voucher);

                  // Sync queue addition
                  final syncItem = SyncQueueItem(
                    id: tempId,
                    type: 'receipt',
                    payload: ReceiptVoucherModel.fromDomain(voucher).toJson(),
                    status: SyncStatus.pending,
                    timestamp: DateTime.now(),
                  );
                  await _db.enqueueSyncItem(syncItem);

                  if (!context.mounted) return;

                  // Sync action trigger in background
                  sl<SyncWorker>().syncPendingItems();

                  Navigator.pop(context);
                  showSuccessSnackBar(
                    context,
                    'Payment Voucher for ${formatCurrency(amount, cs)} queued offline!',
                  );
                  widget.onPaymentLogged();
                },
          child: const Text('LOG RECEIPT'),
        ),
      ],
    );
  }
}
