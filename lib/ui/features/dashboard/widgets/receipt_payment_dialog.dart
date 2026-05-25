import 'package:flutter/material.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../data/models/receipt_voucher_model.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/sync_worker.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/theme/app_theme.dart';
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

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
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
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Payment Amount ($cs)',
                prefixIcon: const Icon(Icons.currency_rupee, color: AppTheme.primaryIndigo),
              ),
            ),
            const SizedBox(height: 16),

            // Dropdown for payment modes
            DropdownButtonFormField<String>(
              initialValue: _paymentMode,
              decoration: const InputDecoration(labelText: 'Payment Mode'),
              items: ['Cash', 'Cheque', 'Bank Transfer', 'Card']
                  .map((mode) => DropdownMenuItem(value: mode, child: Text(mode)))
                  .toList(),
              onChanged: (val) {
                setState(() {
                  _paymentMode = val ?? 'Cash';
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: () async {
            final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
            if (amount <= 0) return;

            final tempId = 'temp_pay_${DateTime.now().millisecondsSinceEpoch}';
            final voucher = ReceiptVoucher(
              id: tempId,
              paymentNumber: 'PAY-TEMP-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
              customerId: widget.customer.id,
              customerName: widget.customer.name,
              allocations: const [],
              amount: amount,
              paymentMode: _paymentMode,
              referenceNumber: 'REF-VAN-${DateTime.now().millisecondsSinceEpoch.toString().substring(10)}',
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppTheme.successEmerald,
                content: Text('Payment Voucher for $cs${amount.toStringAsFixed(2)} queued offline!'),
              ),
            );
            widget.onPaymentLogged();
          },
          child: const Text('LOG RECEIPT'),
        )
      ],
    );
  }
}
