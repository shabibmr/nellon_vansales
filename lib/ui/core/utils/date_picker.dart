import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

Future<DateTime?> showThemedDatePicker(
  BuildContext context, {
  DateTime? initialDate,
  Color color = AppTheme.primaryIndigo,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return showDatePicker(
    context: context,
    initialDate: initialDate ?? DateTime.now(),
    firstDate: firstDate ?? DateTime(2020),
    lastDate: lastDate ?? DateTime(2030),
    builder: (context, child) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Theme(
        data: isDark
            ? ThemeData.dark().copyWith(
                colorScheme: ColorScheme.dark(
                  primary: color,
                  onPrimary: Colors.white,
                  surface: AppTheme.darkSurface,
                  onSurface: AppTheme.darkText,
                ),
              )
            : ThemeData.light().copyWith(
                colorScheme: ColorScheme.light(
                  primary: color,
                  onPrimary: Colors.white,
                  surface: AppTheme.lightSurface,
                  onSurface: AppTheme.lightText,
                ),
              ),
        child: child!,
      );
    },
  );
}
