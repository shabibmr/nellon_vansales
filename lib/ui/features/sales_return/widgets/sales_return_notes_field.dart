import 'package:flutter/material.dart';

class SalesReturnNotesField extends StatelessWidget {
  final TextEditingController controller;
  final bool readOnly;

  const SalesReturnNotesField({
    super.key,
    required this.controller,
    required this.readOnly,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      maxLines: 3,
      decoration: InputDecoration(
        labelText: 'Return Reason / Notes',
        hintText: readOnly ? 'No reason provided' : 'Add reason for return (e.g. damaged goods, expired)...',
        border: const OutlineInputBorder(),
      ),
    );
  }
}
