import 'package:flutter/material.dart';

import '../../../../ui/core/theme/app_theme.dart';

/// Multi-line notes field for the sales order editor.
class SalesOrderNotesField extends StatelessWidget {
  final TextEditingController controller;
  final bool readOnly;

  const SalesOrderNotesField({
    super.key,
    required this.controller,
    required this.readOnly,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: 2,
      readOnly: readOnly,
      enabled: !readOnly,
      decoration: const InputDecoration(
        labelText: 'Order Notes',
        hintText: 'Add remarks or special terms...',
        prefixIcon: Icon(
          Icons.notes,
          color: AppTheme.primaryIndigo,
        ),
      ),
    );
  }
}
