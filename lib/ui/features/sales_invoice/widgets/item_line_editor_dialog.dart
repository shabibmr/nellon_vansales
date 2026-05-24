import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../domain/models/item.dart';
import '../../../../ui/core/theme/app_theme.dart';

/// Interactive modal sheet/dialog to input or adjust the quantity of an invoice line item.
///
/// Handles input validation against the available van stock, taking into account
/// the original quantity if updating an existing line item.
class ItemLineEditorDialog extends StatefulWidget {
  final Item item;
  final int initialQuantity;
  final int originalQuantity; // Original quantity in case we are editing an existing invoice

  const ItemLineEditorDialog({
    super.key,
    required this.item,
    this.initialQuantity = 0,
    this.originalQuantity = 0,
  });

  @override
  State<ItemLineEditorDialog> createState() => _ItemLineEditorDialogState();
}

class _ItemLineEditorDialogState extends State<ItemLineEditorDialog> {
  late TextEditingController _quantityController;
  final _formKey = GlobalKey<FormState>();
  late int _maxAllowedStock;

  @override
  void initState() {
    super.initState();
    _maxAllowedStock = widget.item.stock + widget.originalQuantity;
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
    final subtotal = widget.item.rate * (double.tryParse(_quantityController.text) ?? 0.0);
    final tax = subtotal * (widget.item.taxPercentage / 100);
    final total = subtotal + tax;

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
                    'Line Item Details',
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
                'SKU: ${widget.item.sku} | Rate: ₹${widget.item.rate.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _maxAllowedStock > 0
                      ? AppTheme.successEmerald.withValues(alpha: 0.1)
                      : AppTheme.errorRose.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Available in Van: $_maxAllowedStock items${widget.originalQuantity > 0 ? ' (including ${widget.originalQuantity} originally billed)' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _maxAllowedStock > 0 ? AppTheme.successEmerald : AppTheme.errorRose,
                  ),
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
                  labelText: 'Quantity',
                  hintText: 'Enter quantity',
                  prefixIcon: Icon(Icons.shopping_basket_outlined, color: AppTheme.primaryIndigo),
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) {
                    return 'Please enter quantity';
                  }
                  final qty = int.tryParse(val);
                  if (qty == null || qty <= 0) {
                    return 'Quantity must be greater than 0';
                  }
                  if (qty > _maxAllowedStock) {
                    return 'Exceeds available van stock ($_maxAllowedStock)';
                  }
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
                        Text('₹${widget.item.rate.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('GST (${widget.item.taxPercentage}%):', style: const TextStyle(fontSize: 12)),
                        Text('₹${tax.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(
                          '₹${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppTheme.primaryIndigo,
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
                        backgroundColor: AppTheme.primaryIndigo,
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
