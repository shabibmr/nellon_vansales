import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_pill.dart';
import 'stock_transfer_status.dart';

/// From → To locations + date header shared by the Issue-to-Van and
/// Stock-Unloading editor pages. Shows a [StatusPill] alongside the date
/// when [status] is non-null (viewing/editing an existing transfer).
class StockTransferRouteHeader extends StatelessWidget {
  final String fromLabel;
  final String toLabel;
  final String dateLabel;
  final bool isDark;
  final String? status;

  const StockTransferRouteHeader({
    super.key,
    required this.fromLabel,
    required this.toLabel,
    required this.dateLabel,
    required this.isDark,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? const Color(0xFF334155)
                : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  fromLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: AppTheme.primaryIndigo,
              ),
              Expanded(
                child: Text(
                  toLabel,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.event_outlined, size: 16, color: secondary),
              const SizedBox(width: 6),
              Text(
                'Date',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: secondary,
                ),
              ),
              const Spacer(),
              Text(
                dateLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (status != null) ...[
                const SizedBox(width: 10),
                StatusPill(
                  label: stockTransferStatusLabel(status!),
                  color: stockTransferStatusColor(status!),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
