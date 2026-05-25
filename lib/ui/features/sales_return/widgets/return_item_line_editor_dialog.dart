import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../domain/models/item.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';

/// Dialog to input or adjust the quantity of a sales return line item.
class ReturnItemLineEditorDialog extends StatefulWidget {
  final Item item;
  final int initialQuantity;

  const ReturnItemLineEditorDialog({
    super.key,
    required this.item,
    this.initialQuantity = 0,
  });

  @override
  State<ReturnItemLineEditorDialog> createState() => _ReturnItemLineEditorDialogState();
}

class _ReturnItemLineEditorDialogState extends State<ReturnItemLineEditorDialog> {
  late TextEditingController _quantityController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(
      text: widget.initialQuantity > 0 ? widget.initialQuantity.toString() : '1',
    );
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final qty = int.tryParse(_quantityController.text) ?? 0;
      Navigator.pop(context, qty);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;
    final qty = double.tryParse(_quantityController.text) ?? 0.0;
    final total = widget.item.rate * qty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Return Item Details',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const Divider(height: 24),
              Text(
                widget.item.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'SKU: ${widget.item.sku} | Rate: $cs${widget.item.rate.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _quantityController,
                keyboardType: TextInputType.number,
                autofocus: true,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Return Quantity',
                  hintText: 'Enter quantity to return',
                  prefixIcon: Icon(Icons.undo_rounded, color: AppTheme.warningAmber),
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Please enter quantity';
                  final qty = int.tryParse(val);
                  if (qty == null || qty <= 0) return 'Quantity must be greater than 0';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Rate:', style: TextStyle(fontSize: 12)),
                        Text('$cs${widget.item.rate.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Return Total:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(
                          '$cs${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppTheme.warningAmber,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.warningAmber,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(widget.initialQuantity > 0 ? 'Update' : 'Add Item'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
