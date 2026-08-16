import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../cubit/cash_closing_cubit.dart';
import '../cubit/cash_closing_state.dart';

/// Modal dialog for filing the daily end-of-trip cash closing reconciliation.
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

  /// Presents the dialog provided with [CashClosingCubit].
  static Future<void> show(
    BuildContext context, {
    required double todaySales,
    required double todayPayments,
    required double todayExpenses,
    required VoidCallback onSessionReconciled,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<CashClosingCubit>(
        create: (_) => CashClosingCubit(
          salesRepository: sl<SalesRepository>(),
          syncRepository: sl<SyncRepository>(),
        ),
        child: CashClosingDialog(
          todaySales: todaySales,
          todayPayments: todayPayments,
          todayExpenses: todayExpenses,
          onSessionReconciled: onSessionReconciled,
        ),
      ),
    );
  }

  @override
  State<CashClosingDialog> createState() => _CashClosingDialogState();
}

class _CashClosingDialogState extends State<CashClosingDialog> {
  final _physicalCashController = TextEditingController();
  final _notesController = TextEditingController();
  late final TextEditingController _openingBalanceController;

  @override
  void initState() {
    super.initState();
    final lastClosing = sl<SalesRepository>().getLocalCashClosing();
    final opening = lastClosing?.closingBalance ?? 0.0;
    _openingBalanceController = TextEditingController(
      text: opening == 0 ? '' : opening.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _physicalCashController.dispose();
    _notesController.dispose();
    _openingBalanceController.dispose();
    super.dispose();
  }

  double get _openingBalance =>
      double.tryParse(_openingBalanceController.text.trim()) ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;
    final expectedClosing =
        _openingBalance + widget.todayPayments - widget.todayExpenses;

    return BlocListener<CashClosingCubit, CashClosingState>(
      listener: (context, state) {
        if (state is CashClosingSuccess) {
          Navigator.pop(context);

          final closing = state.closing;
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
                ),
              ],
            ),
          );
          widget.onSessionReconciled();
        } else if (state is CashClosingFailure) {
          showErrorSnackBar(context, state.message);
        }
      },
      child: BlocBuilder<CashClosingCubit, CashClosingState>(
        builder: (context, state) {
          final isSubmitting = state is CashClosingSubmitting;

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
                  TextFormField(
                    controller: _openingBalanceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Morning cash float ($cs)',
                      hintText: 'Enter opening cash in the van',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Total Invoiced Sales: $cs${widget.todaySales.toStringAsFixed(2)}',
                  ),
                  Text(
                    'Total Cash Collected: $cs${widget.todayPayments.toStringAsFixed(2)}',
                  ),
                  Text(
                    'Total Claimed Expenses: $cs${widget.todayExpenses.toStringAsFixed(2)}',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Expected Cash In Hand: $cs${expectedClosing.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryIndigo,
                    ),
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
                    decoration: const InputDecoration(
                      labelText: 'Remarks / Discrepancy Notes',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(context),
                child: const Text('CANCEL'),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () {
                        final counted =
                            double.tryParse(
                                  _physicalCashController.text.trim(),
                                ) ??
                                0.0;
                        final notes = _notesController.text.trim();

                        context.read<CashClosingCubit>().submitCashClosing(
                              todaySales: widget.todaySales,
                              todayPayments: widget.todayPayments,
                              todayExpenses: widget.todayExpenses,
                              physicalCashCounted: counted,
                              notes: notes,
                              openingBalance: _openingBalance,
                            );
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('SUBMIT RECONCILIATION'),
              ),
            ],
          );
        },
      ),
    );
  }
}
