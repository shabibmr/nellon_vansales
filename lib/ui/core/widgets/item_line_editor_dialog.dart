import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../domain/models/item.dart';
import '../theme/app_theme.dart';
import '../extensions/org_context_extension.dart';
import '../utils/currency.dart';
import 'dialog_scaffolding.dart';

/// Unified line-item quantity editor dialog shared by sales order and invoice flows.
///
/// [allowUnlimitedQuantity] — when true (order mode) any positive qty is accepted;
/// when false (invoice mode) qty is capped at `item.stock + originalQuantity`.
class SharedItemLineEditorDialog extends StatefulWidget {
  final Item item;
  final int initialQuantity;
  final int originalQuantity;
  final bool allowUnlimitedQuantity;
  final String title;
  final double? initialRate;
  final double? initialDiscount;

  const SharedItemLineEditorDialog({
    super.key,
    required this.item,
    this.initialQuantity = 0,
    this.originalQuantity = 0,
    this.allowUnlimitedQuantity = false,
    this.title = 'Line Item Details',
    this.initialRate,
    this.initialDiscount,
  });

  @override
  State<SharedItemLineEditorDialog> createState() => _SharedItemLineEditorDialogState();
}

class _SharedItemLineEditorDialogState extends State<SharedItemLineEditorDialog> {
  late TextEditingController _quantityController;
  late TextEditingController _rateController;
  late TextEditingController _discountController;
  final _formKey = GlobalKey<FormState>();
  late int _maxAllowedStock;

  @override
  void initState() {
    super.initState();
    _maxAllowedStock = widget.item.stock + widget.originalQuantity;
    _quantityController = TextEditingController(
      text: widget.initialQuantity > 0 ? widget.initialQuantity.toString() : '1',
    );
    _rateController = TextEditingController(
      text: (widget.initialRate ?? widget.item.rate).toStringAsFixed(2),
    );
    _discountController = TextEditingController(
      text: (widget.initialDiscount ?? 0.0).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _rateController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final qty = int.tryParse(_quantityController.text) ?? 0;
      final rate = double.tryParse(_rateController.text) ?? widget.item.rate;
      final discount = double.tryParse(_discountController.text) ?? 0.0;
      Navigator.pop(context, (qty, rate, discount));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;
    final qty = int.tryParse(_quantityController.text) ?? 0;
    final rate = double.tryParse(_rateController.text) ?? 0.0;
    final discount = double.tryParse(_discountController.text) ?? 0.0;

    final subtotal = rate * qty;
    final tax = (subtotal - discount) * (widget.item.taxPercentage / 100);
    final total = subtotal + tax - discount;
    final displayStock = widget.allowUnlimitedQuantity ? widget.item.stock : _maxAllowedStock;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DialogHeader(title: widget.title),
                Text(
                  widget.item.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  'SKU: ${widget.item.sku} | Standard Rate: ${formatCurrency(widget.item.rate, cs)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: displayStock > 0
                        ? AppTheme.successEmerald.withValues(alpha: 0.1)
                        : AppTheme.errorRose.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.allowUnlimitedQuantity
                        ? 'Available in Van: $displayStock items'
                        : 'Available in Van: $displayStock items'
                              '${widget.originalQuantity > 0 ? ' (including ${widget.originalQuantity} originally billed)' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: displayStock > 0 ? AppTheme.successEmerald : AppTheme.errorRose,
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
                    if (val == null || val.isEmpty) return 'Please enter quantity';
                    final qty = int.tryParse(val);
                    if (qty == null || qty <= 0) return 'Quantity must be greater than 0';
                    if (!widget.allowUnlimitedQuantity && qty > _maxAllowedStock) {
                      return 'Exceeds available van stock ($_maxAllowedStock)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _rateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Unit Rate ($cs)',
                    hintText: 'Enter rate',
                    prefixIcon: const Icon(Icons.monetization_on_outlined, color: AppTheme.primaryIndigo),
                  ),
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Please enter rate';
                    final parsedRate = double.tryParse(val);
                    if (parsedRate == null || parsedRate <= 0) return 'Rate must be greater than 0';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _discountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Discount ($cs)',
                    hintText: 'Enter discount',
                    prefixIcon: const Icon(Icons.local_offer_outlined, color: AppTheme.primaryIndigo),
                  ),
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Please enter discount';
                    final parsedDiscount = double.tryParse(val);
                    if (parsedDiscount == null || parsedDiscount < 0) return 'Discount must be 0 or greater';
                    final qty = int.tryParse(_quantityController.text) ?? 0;
                    final currentRate = double.tryParse(_rateController.text) ?? 0.0;
                    if (parsedDiscount > (currentRate * qty)) {
                      return 'Discount cannot exceed subtotal';
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
                          const Text('Subtotal:', style: TextStyle(fontSize: 12)),
                          Text(formatCurrency(subtotal, cs), style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Discount:', style: TextStyle(fontSize: 12)),
                          Text(formatCurrency(discount, cs), style: const TextStyle(fontSize: 12, color: AppTheme.errorRose)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('VAT (${widget.item.taxPercentage}%):', style: const TextStyle(fontSize: 12)),
                          Text(formatCurrency(tax, cs), style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text(
                            formatCurrency(total, cs),
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
                DialogActionButtons(
                  submitLabel: widget.initialQuantity > 0 ? 'Update' : 'Add Item',
                  onSubmit: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
