import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

/// Reusable date-range filter card used on list pages.
class DateRangeFilterCard extends StatelessWidget {
  final DateTime? startDate;
  final DateTime? endDate;
  final VoidCallback onStartTap;
  final VoidCallback onEndTap;
  final VoidCallback? onClear;
  final Color accentColor;

  const DateRangeFilterCard({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.onStartTap,
    required this.onEndTap,
    this.onClear,
    this.accentColor = AppTheme.primaryIndigo,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fmt = DateFormat('dd MMM yyyy');
    final hasFilter = startDate != null || endDate != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Card(
        elevation: isDark ? 0 : 2,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.filter_alt_outlined, size: 18, color: accentColor),
                  const SizedBox(width: 6),
                  const Text(
                    'Filter by Date Range',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const Spacer(),
                  if (hasFilter)
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: onClear,
                      child: const Text(
                        'Clear',
                        style: TextStyle(
                          color: AppTheme.errorRose,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _DatePickerBox(
                      label: startDate != null
                          ? fmt.format(startDate!)
                          : 'Start Date',
                      hasValue: startDate != null,
                      accentColor: accentColor,
                      isDark: isDark,
                      onTap: onStartTap,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text('to', style: TextStyle(fontSize: 12)),
                  ),
                  Expanded(
                    child: _DatePickerBox(
                      label: endDate != null
                          ? fmt.format(endDate!)
                          : 'End Date',
                      hasValue: endDate != null,
                      accentColor: accentColor,
                      isDark: isDark,
                      onTap: onEndTap,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DatePickerBox extends StatelessWidget {
  final String label;
  final bool hasValue;
  final Color accentColor;
  final bool isDark;
  final VoidCallback onTap;

  const _DatePickerBox({
    required this.label,
    required this.hasValue,
    required this.accentColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
          borderRadius: BorderRadius.circular(8),
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        ),
        child: Row(
          children: [
            Icon(Icons.date_range, size: 16, color: accentColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: hasValue
                      ? (isDark ? AppTheme.darkText : AppTheme.lightText)
                      : (isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
