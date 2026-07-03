import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Bottom footer shared by all editor pages.
/// Shows totals rows + a full-width save button with optional trailing widget.
class EditorFooter extends StatelessWidget {
  final List<({String label, String value, bool emphasize})> rows;
  final String buttonLabel;
  final Color buttonColor;
  final Color accentColor;
  final VoidCallback? onSave;
  final Widget? trailing;

  const EditorFooter({
    super.key,
    required this.rows,
    required this.buttonLabel,
    required this.onSave,
    this.buttonColor = AppTheme.primaryIndigo,
    this.accentColor = AppTheme.primaryIndigo,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < rows.length; i++) ...[
                if (i > 0 && rows[i].emphasize && !rows[i - 1].emphasize)
                  const Divider(height: 16),
                if (i > 0 && !(rows[i].emphasize && !rows[i - 1].emphasize))
                  const SizedBox(height: 4),
                _TotalsRow(label: rows[i].label, value: rows[i].value, emphasize: rows[i].emphasize, accentColor: accentColor),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: buttonColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(buttonLabel),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(height: 16),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;
  final Color accentColor;

  const _TotalsRow({
    required this.label,
    required this.value,
    required this.emphasize,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (emphasize) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: accentColor,
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
          ),
        ),
        Text(value),
      ],
    );
  }
}
