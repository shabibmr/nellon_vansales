import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'editor_footer.dart';

/// Modal sheet showing a voucher's totals breakdown plus its document
/// actions (PDF/print/thermal/share/convert), reached via the editor
/// page's AppBar share icon so this content no longer lives in a
/// persistent bottom bar that can crowd out form content.
class VoucherDetailsSheet extends StatelessWidget {
  final List<({String label, String value, bool emphasize})> rows;
  final Widget? actions;

  const VoucherDetailsSheet({super.key, required this.rows, this.actions});

  static Future<void> show(
    BuildContext context, {
    required List<({String label, String value, bool emphasize})> rows,
    Widget? actions,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VoucherDetailsSheet(rows: rows, actions: actions),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Material(
          color: surface,
          elevation: 12,
          shadowColor: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(top: BorderSide(color: border)),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    Text(
                      'Voucher Details',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: isDark ? AppTheme.darkText : AppTheme.lightText,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final row in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: VoucherTotalsRow(
                          label: row.label,
                          value: row.value,
                          emphasize: row.emphasize,
                          accentColor: AppTheme.primaryIndigo,
                        ),
                      ),
                    if (actions != null) ...[
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 16),
                      actions!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
