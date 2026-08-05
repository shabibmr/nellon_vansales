import 'package:flutter/material.dart';

/// Confirms discarding unsaved form edits before a Zoho refresh rehydrates the form.
Future<bool> confirmDiscardEditsForRefresh(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Discard local edits?'),
      content: const Text(
        'You have unsaved changes. Refreshing from Zoho Books will replace '
        'the form with the server copy.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('REFRESH'),
        ),
      ],
    ),
  );
  return result == true;
}
