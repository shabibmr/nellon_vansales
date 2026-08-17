import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/repositories/cash_closing_repository.dart';
import 'bloc/auth_bloc.dart';

/// Signs the user out unless today's cash closing is still pending.
///
/// When [hasPendingCashClosing] is omitted, the live cash-closing
/// repository is consulted. Pass it explicitly in tests to skip the lookup.
Future<void> attemptLogout(
  BuildContext context, {
  bool? hasPendingCashClosing,
}) async {
  final pending = hasPendingCashClosing ??
      context.read<CashClosingRepository>().hasPendingCashClosingForToday();
  if (!pending) {
    context.read<AuthBloc>().add(LogoutRequested());
    return;
  }

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Cash Closing Required'),
      content: const Text(
        "You have unreconciled sales activity today. Please complete "
        "today's Cash Closing from the Dashboard before logging out.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
