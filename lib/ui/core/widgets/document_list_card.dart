import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'status_pill.dart';

/// Reusable list-row card for sales orders, invoices, and receipts.
class DocumentListCard extends StatelessWidget {
  final String docNumber;
  final String customerName;
  final String date;
  /// Optional extra subtitle line beneath the customer name (e.g. payment mode).
  final String? subtitle;
  final String total;
  final int? itemCount;
  final bool isPendingSync;
  /// Optional extra status pill shown beside the sync pill (e.g. "Converted").
  final String? extraBadgeLabel;
  final Color extraBadgeColor;
  final Color accentColor;
  final VoidCallback onTap;

  const DocumentListCard({
    super.key,
    required this.docNumber,
    required this.customerName,
    required this.date,
    this.subtitle,
    required this.total,
    this.itemCount,
    required this.isPendingSync,
    required this.onTap,
    this.extraBadgeLabel,
    this.extraBadgeColor = AppTheme.successEmerald,
    this.accentColor = AppTheme.primaryIndigo,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          docNumber,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusPill(
                          label: isPendingSync ? 'Pending Sync' : 'Synced',
                          color: isPendingSync ? AppTheme.warningAmber : AppTheme.successEmerald,
                        ),
                        if (extraBadgeLabel != null) ...[
                          const SizedBox(width: 6),
                          StatusPill(label: extraBadgeLabel!, color: extraBadgeColor),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      customerName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle ?? 'Date: $date',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    total,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: accentColor,
                    ),
                  ),
                  if (itemCount != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '$itemCount items',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_right,
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
