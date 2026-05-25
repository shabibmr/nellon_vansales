import 'package:flutter/material.dart';
import '../../../../domain/models/cash_closing.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/sync_worker.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';

/// Modal dialog for filing the daily end-of-trip [CashClosing] reconciliation.
///
/// Prompts the agent to count and input their physical cash in hand and compiles a detailed
/// breakdown of opening cash, sales, payments, and expenses to flag surpluses or shortages.
class CashClosingDialog extends StatefulWidget {
  /// Daily sales invoice total.
  final double todaySales;

  /// Daily collected receipts total.
  final double todayPayments;

  /// Daily filed expenses total.
  final double todayExpenses;

  /// Callback fired when the daily session is successfully compiled and saved.
  final VoidCallback onSessionReconciled;

  /// Creates a new [CashClosingDialog].
  const CashClosingDialog({
    super.key,
    required this.todaySales,
    required this.todayPayments,
    required this.todayExpenses,
    required this.onSessionReconciled,
  });

  @override
  State<CashClosingDialog> createState() => _CashClosingDialogState();
}

class _CashClosingDialogState extends State<CashClosingDialog> {
  final _physicalCashController = TextEditingController();
  final _notesController = TextEditingController();
  final HiveDatabaseService _db = sl<HiveDatabaseService>();

  @override
  void dispose() {
    _physicalCashController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;
    const openingBalance = 1000.00; // Mock opening morning float in the van
    final expectedClosing = openingBalance + widget.todayPayments - widget.todayExpenses;

    return AlertDialog(
      title: const Text('Daily Cash Closing'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'End of Session Reconciliation. Summarizes today\'s transactions.',
              style: TextStyle(fontSize: 12),
            ),
            const Divider(height: 24, color: Color(0xFF334155)),
            Text('Morning Cash Float: $cs${openingBalance.toStringAsFixed(2)}'),
            Text('Total Invoiced Sales: $cs${widget.todaySales.toStringAsFixed(2)}'),
            Text('Total Cash Collected: $cs${widget.todayPayments.toStringAsFixed(2)}'),
            Text('Total Claimed Expenses: $cs${widget.todayExpenses.toStringAsFixed(2)}'),
            const SizedBox(height: 6),
            Text(
              'Expected Cash In Hand: $cs${expectedClosing.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryIndigo),
            ),
            const Divider(height: 24, color: Color(0xFF334155)),
            TextFormField(
              controller: _physicalCashController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Physical Cash Counted ($cs)',
                hintText: 'Enter physical cash in hand',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Remarks / Discrepancy Notes'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        ElevatedButton(
          onPressed: () async {
            final counted = double.tryParse(_physicalCashController.text.trim()) ?? 0.0;
            final notes = _notesController.text.trim();

            final closing = CashClosing(
              id: 'closing_${DateTime.now().millisecondsSinceEpoch}',
              date: DateTime.now(),
              openingBalance: openingBalance,
              totalSalesInvoices: widget.todaySales,
              totalReceiptsCollected: widget.todayPayments,
              totalExpenses: widget.todayExpenses,
              closingBalance: counted,
              notes: notes,
              isPendingSync: true,
            );

            await _db.saveLocalCashClosing(closing);

            // Generate sync packet
            final syncItem = SyncQueueItem(
              id: closing.id,
              type: 'expense', // Map closing as custom expense sheet or sync separately
              payload: {
                'amount': closing.reportedDifference.abs(),
                'category': 'Miscellaneous',
                'description': 'Daily Cash Closing: counted: $counted, expected: $expectedClosing. Difference: ${closing.reportedDifference.toStringAsFixed(2)}. Notes: $notes',
                'date': closing.date.toIso8601String().split('T')[0],
                'isPendingSync': true,
              },
              status: SyncStatus.pending,
              timestamp: DateTime.now(),
            );
            await _db.enqueueSyncItem(syncItem);

            if (!context.mounted) return;

            sl<SyncWorker>().syncPendingItems();

            Navigator.pop(context);
            
            final difference = closing.reportedDifference;
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Session Reconciled'),
                content: Text(
                  difference == 0
                      ? 'Session closed successfully with zero cash discrepancy!'
                      : 'Session closed. Cash discrepancy detected: ${difference > 0 ? "+" : ""}$cs${difference.toStringAsFixed(2)}. Discrepancy is logged for Zoho reconciliation.',
                ),
                actions: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK'),
                  )
                ],
              ),
            );
            widget.onSessionReconciled();
          },
          child: const Text('SUBMIT RECONCILIATION'),
        ),
      ],
    );
  }
}
