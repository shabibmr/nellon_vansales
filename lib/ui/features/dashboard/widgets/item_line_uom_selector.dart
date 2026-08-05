import 'package:flutter/material.dart';

class ItemLineUomSelector extends StatelessWidget {
  final String selectedUom;
  final List<String> unitOptions;
  final bool hasUnitOptions;
  final ValueChanged<String?>? onChanged;
  final InputDecoration decoration;

  const ItemLineUomSelector({
    super.key,
    required this.selectedUom,
    required this.unitOptions,
    required this.hasUnitOptions,
    required this.onChanged,
    required this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: ValueKey('uom_$selectedUom'),
      initialValue: unitOptions.contains(selectedUom) ? selectedUom : null,
      isExpanded: true,
      decoration: decoration,
      hint: const Text('—'),
      items: unitOptions
          .map(
            (u) => DropdownMenuItem<String>(
              value: u,
              child: Text(u, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: hasUnitOptions ? onChanged : null,
    );
  }
}
