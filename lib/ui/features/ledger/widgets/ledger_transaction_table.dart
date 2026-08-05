import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../domain/models/customer_ledger.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';

class LedgerTransactionTable extends StatelessWidget {
  final List<LedgerTransaction> transactions;
  final bool isDark;
  final DateFormat shortDate;
  final void Function(LedgerTransaction tx)? onTransactionTap;

  const LedgerTransactionTable({
    super.key,
    required this.transactions,
    required this.isDark,
    required this.shortDate,
    this.onTransactionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.list_alt_outlined,
              size: 16,
              color: AppTheme.primaryIndigo,
            ),
            const SizedBox(width: 6),
            Text(
              'Transactions  (${transactions.length})',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (transactions.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'No transactions in this period.',
                style: TextStyle(
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ),
            ),
          )
        else
          Column(
            children: [
              _TableHeader(isDark: isDark),
              const Divider(height: 1),
              ...transactions.map(
                (tx) => _TransactionRow(
                  tx: tx,
                  isDark: isDark,
                  shortDate: shortDate,
                  onTap: () => onTransactionTap?.call(tx),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  final bool isDark;
  const _TableHeader({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
    );
    return Container(
      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text('DATE', style: style)),
          Expanded(child: Text('DESCRIPTION', style: style)),
          SizedBox(
            width: 72,
            child: Text('DEBIT', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 72,
            child: Text('CREDIT', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 80,
            child: Text('BALANCE', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final LedgerTransaction tx;
  final bool isDark;
  final DateFormat shortDate;
  final VoidCallback? onTap;

  const _TransactionRow({
    required this.tx,
    required this.isDark,
    required this.shortDate,
    this.onTap,
  });

  Color get _typeColor {
    switch (tx.type) {
      case 'invoice':
      case 'debit_note':
        return AppTheme.warningAmber;
      case 'payment':
      case 'credit_note':
        return AppTheme.successEmerald;
      default:
        return AppTheme.primaryIndigo;
    }
  }

  IconData get _typeIcon {
    switch (tx.type) {
      case 'invoice':
        return Icons.receipt_long_outlined;
      case 'payment':
        return Icons.payments_outlined;
      case 'credit_note':
        return Icons.remove_circle_outline;
      case 'debit_note':
        return Icons.add_circle_outline;
      default:
        return Icons.swap_horiz_outlined;
    }
  }

  bool get _canOpen {
    final type = tx.type.toLowerCase().trim();
    return tx.transactionId.isNotEmpty &&
        (type == 'invoice' ||
            type == 'payment' ||
            type == 'credit_note' ||
            type == 'debit_note');
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;
    final textStyle = TextStyle(
      fontSize: 12,
      color: isDark ? AppTheme.darkText : AppTheme.lightText,
    );

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _canOpen ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: Text(
                      shortDate.format(tx.date),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Icon(_typeIcon, size: 14, color: _typeColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tx.description.isNotEmpty
                                    ? tx.description
                                    : tx.transactionNumber,
                                style: textStyle.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: _canOpen
                                      ? AppTheme.primaryIndigo
                                      : null,
                                  decoration: _canOpen
                                      ? TextDecoration.underline
                                      : null,
                                  decorationColor: AppTheme.primaryIndigo
                                      .withValues(alpha: 0.4),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (tx.transactionNumber.isNotEmpty &&
                                  tx.description != tx.transactionNumber)
                                Text(
                                  tx.transactionNumber,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isDark
                                        ? AppTheme.darkTextSecondary
                                        : AppTheme.lightTextSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (_canOpen)
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.lightTextSecondary,
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      tx.debit > 0
                          ? '$cs${tx.debit.toStringAsFixed(2)}'
                          : '-',
                      style: textStyle.copyWith(
                        color: tx.debit > 0
                            ? AppTheme.warningAmber
                            : Colors.transparent,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      tx.credit > 0
                          ? '$cs${tx.credit.toStringAsFixed(2)}'
                          : '-',
                      style: textStyle.copyWith(
                        color: tx.credit > 0
                            ? AppTheme.successEmerald
                            : Colors.transparent,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      '$cs${tx.balance.toStringAsFixed(2)}',
                      style: textStyle.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Divider(
          height: 1,
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ],
    );
  }
}
