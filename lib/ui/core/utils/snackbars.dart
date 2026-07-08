import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

void showSuccessSnackBar(
  BuildContext context,
  String message, {
  SnackBarBehavior behavior = SnackBarBehavior.fixed,
  ShapeBorder? shape,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: AppTheme.successEmerald,
      behavior: behavior,
      shape: shape,
      content: Text(message),
    ),
  );
}

void showErrorSnackBar(
  BuildContext context,
  String message, {
  SnackBarBehavior behavior = SnackBarBehavior.fixed,
  ShapeBorder? shape,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: AppTheme.errorRose,
      behavior: behavior,
      shape: shape,
      content: Text(message),
    ),
  );
}
