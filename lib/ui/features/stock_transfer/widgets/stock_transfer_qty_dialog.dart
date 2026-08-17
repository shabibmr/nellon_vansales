import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../domain/models/item.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/quantity_format.dart';

/// Quantity + multi-UOM entry dialog for a stock-transfer line. Unlike
/// [SharedItemLineEditorDialog], a transfer line has no rate/tax — this only
/// asks for a quantity and (when the item has more than one known unit) the
/// unit it's entered in.
class StockTransferQtyDialog {
  const StockTransferQtyDialog._();

  /// Shows the dialog and returns the entered quantity (base units via
  /// [conversionRate]) plus the unit it was entered in, or null if cancelled.
  static Future<({double quantity, String uom, double conversionRate})?> show(
    BuildContext context, {
    required Item item,
    double initialQuantity = 0,
    String? initialUom,
    double currentStock = 0,
  }) {
    return showDialog<({double quantity, String uom, double conversionRate})>(
      context: context,
      builder: (_) => _StockTransferQtyDialogBody(
        item: item,
        initialQuantity: initialQuantity,
        initialUom: initialUom,
        currentStock: currentStock,
      ),
    );
  }
}

class _StockTransferQtyDialogBody extends StatefulWidget {
  final Item item;
  final double initialQuantity;
  final String? initialUom;
  final double currentStock;

  const _StockTransferQtyDialogBody({
    required this.item,
    required this.initialQuantity,
    required this.initialUom,
    required this.currentStock,
  });

  @override
  State<_StockTransferQtyDialogBody> createState() =>
      _StockTransferQtyDialogBodyState();
}

class _StockTransferQtyDialogBodyState
    extends State<_StockTransferQtyDialogBody> {
  late final TextEditingController _controller;
  late String _selectedUom;

  List<String> get _unitOptions => [
    if (widget.item.uom.trim().isNotEmpty) widget.item.uom.trim(),
    ...widget.item.unitConversions.map((c) => c.targetUnit),
  ];

  @override
  void initState() {
    super.initState();
    final fromLine = widget.initialUom?.trim() ?? '';
    final fromItem = widget.item.uom.trim();
    final initialUom = fromLine.isNotEmpty ? fromLine : fromItem;
    final options = _unitOptions;
    _selectedUom = options.contains(initialUom)
        ? initialUom
        : (options.isNotEmpty ? options.first : '');
    final entered = widget.initialQuantity > 0
        ? widget.initialQuantity /
              (widget.item.conversionRateFor(_selectedUom) <= 0
                  ? 1.0
                  : widget.item.conversionRateFor(_selectedUom))
        : 0.0;
    _controller = TextEditingController(
      text: entered > 0 ? formatQuantity(entered) : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final qty = double.tryParse(_controller.text) ?? 0;
    if (qty <= 0) return;
    Navigator.pop<({double quantity, String uom, double conversionRate})>(
      context,
      (
        quantity: qty,
        uom: _selectedUom,
        conversionRate: widget.item.conversionRateFor(_selectedUom),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final decimals =
        widget.item.conversionFor(_selectedUom)?.quantityDecimalPlaces ?? 3;
    final unitOptions = _unitOptions;
    final stockLabel = widget.item.uom.trim().isNotEmpty
        ? '${formatQuantity(widget.currentStock)} ${widget.item.uom.trim()}'
        : formatQuantity(widget.currentStock);

    return AlertDialog(
      title: Text(widget.item.name),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.successEmerald.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Current stock: $stockLabel',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.successEmerald,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: decimals > 0
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.number,
                inputFormatters: [
                  decimals > 0
                      ? FilteringTextInputFormatter.allow(
                          RegExp('^\\d*\\.?\\d{0,$decimals}'),
                        )
                      : FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  suffixText: _selectedUom.isNotEmpty ? _selectedUom : null,
                ),
              ),
              if (unitOptions.length > 1) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedUom,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                    isDense: true,
                  ),
                  items: unitOptions
                      .map(
                        (u) => DropdownMenuItem<String>(
                          value: u,
                          child: Text(u, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (u) {
                    if (u != null) setState(() => _selectedUom = u);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.initialQuantity > 0 ? 'Update' : 'Add'),
        ),
      ],
    );
  }
}
