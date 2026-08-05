import 'package:flutter/material.dart';

class SalesInvoiceNotesField extends StatelessWidget {
  final TextEditingController controller;
  final bool readOnly;
  final ValueChanged<String>? onChanged;

  const SalesInvoiceNotesField({
    super.key,
    required this.controller,
    required this.readOnly,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      maxLines: 3,
      onChanged: readOnly ? null : onChanged,
      decoration: InputDecoration(
        labelText: 'Notes / Remarks',
        hintText: readOnly ? 'No notes provided' : 'Add internal notes or instructions...',
        border: const OutlineInputBorder(),
      ),
    );
  }
}
