import 'package:flutter/material.dart';
import '../../../../domain/models/customer_ledger.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';

class CustomerLedgerHeader extends StatelessWidget {
  final CustomerLedger ledger;
  final bool isDark;

  const CustomerLedgerHeader({
    super.key,
    required this.ledger,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;
    return Card(
      color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person, color: AppTheme.primaryIndigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ledger.customerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SummaryChip(
                  label: 'Opening Balance',
                  value: '$cs${ledger.openingBalance.toStringAsFixed(2)}',
                  color: AppTheme.primaryIndigo,
                  isDark: isDark,
                ),
                _SummaryChip(
                  label: 'Total Invoiced',
                  value: '$cs${ledger.totalDebits.toStringAsFixed(2)}',
                  color: AppTheme.warningAmber,
                  isDark: isDark,
                ),
                _SummaryChip(
                  label: 'Total Received',
                  value: '$cs${ledger.totalCredits.toStringAsFixed(2)}',
                  color: AppTheme.successEmerald,
                  isDark: isDark,
                ),
                _SummaryChip(
                  label: 'Closing Balance',
                  value: '$cs${ledger.closingBalance.toStringAsFixed(2)}',
                  color: ledger.closingBalance > 0
                      ? AppTheme.errorRose
                      : AppTheme.successEmerald,
                  isDark: isDark,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: isDark ? AppTheme.darkText : AppTheme.lightText,
            ),
          ),
        ],
      ),
    );
  }
}
