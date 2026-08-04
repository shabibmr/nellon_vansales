import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../ui/core/theme/app_theme.dart';

/// Labeled date row card (order date, expected shipment, etc.).
class SalesOrderDateCard extends StatelessWidget {
  final String label;
  final DateTime date;
  final IconData icon;
  final Color accentColor;

  /// When null the card is display-only (no chevron / ink).
  final VoidCallback? onTap;

  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  const SalesOrderDateCard({
    super.key,
    required this.label,
    required this.date,
    required this.icon,
    required this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    final editable = onTap != null;

    final body = Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: accentColor.withValues(alpha: 0.1),
            child: Icon(icon, color: accentColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: secondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _dateFormat.format(date),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (editable) Icon(Icons.keyboard_arrow_right, color: secondary),
        ],
      ),
    );

    return Card(
      child: editable
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: body,
            )
          : body,
    );
  }
}
