import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/models/item.dart';
import '../theme/app_theme.dart';
import '../extensions/org_context_extension.dart';
import '../utils/currency.dart';
import '../cubit/line_editor_cubit.dart';
import 'dialog_scaffolding.dart';

/// Content width at/above which fields and totals use a single horizontal row.
const double _kWideLayoutMinWidth = 400;

/// Unified line-item quantity editor dialog shared by sales order and invoice flows.
///
/// [allowUnlimitedQuantity] — when true (order mode) any positive qty is accepted;
/// when false (invoice mode) qty is capped at `item.stock + originalQuantity`.
///
/// Layout is mobile-first and responsive: narrow phones use a compact 2-column
/// field grid; wider surfaces put quantity/rate/discount on one row. Content is
/// sized to fit without an always-on scroll view.
class SharedItemLineEditorDialog extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return BlocProvider<LineEditorCubit>(
      create: (_) => LineEditorCubit(
        initialQuantity: initialQuantity,
        initialRate: initialRate ?? item.rate,
        initialDiscount: initialDiscount ?? 0.0,
        taxPercentage: item.taxPercentage,
      ),
      child: _LineEditorDialogBody(
        item: item,
        initialQuantity: initialQuantity,
        originalQuantity: originalQuantity,
        allowUnlimitedQuantity: allowUnlimitedQuantity,
        title: title,
        initialRate: initialRate,
        initialDiscount: initialDiscount,
      ),
    );
  }
}

/// Internal stateful shell — only kept stateful to own the [TextEditingController]s
/// and [GlobalKey<FormState>], which must be widget-local for IME compatibility.
/// All reactive display logic (totals panel) uses [BlocBuilder]; no [setState] is called.
class _LineEditorDialogBody extends StatefulWidget {
  final Item item;
  final int initialQuantity;
  final int originalQuantity;
  final bool allowUnlimitedQuantity;
  final String title;
  final double? initialRate;
  final double? initialDiscount;

  const _LineEditorDialogBody({
    required this.item,
    required this.initialQuantity,
    required this.originalQuantity,
    required this.allowUnlimitedQuantity,
    required this.title,
    this.initialRate,
    this.initialDiscount,
  });

  @override
  State<_LineEditorDialogBody> createState() => _LineEditorDialogBodyState();
}

class _LineEditorDialogBodyState extends State<_LineEditorDialogBody> {
  late final TextEditingController _quantityController;
  late final TextEditingController _rateController;
  late final TextEditingController _discountController;
  final _formKey = GlobalKey<FormState>();
  late final int _maxAllowedStock;

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

  InputDecoration _denseDecoration({
    required String labelText,
    required String hintText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _buildQuantityField() {
    return TextFormField(
      controller: _quantityController,
      keyboardType: TextInputType.number,
      autofocus: true,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (val) {
        final qty = int.tryParse(val) ?? 0;
        context.read<LineEditorCubit>().setQuantity(qty);
      },
      decoration: _denseDecoration(
        labelText: 'Quantity',
        hintText: 'Qty',
      ),
      validator: (val) {
        if (val == null || val.isEmpty) {
          return 'Required';
        }
        final qty = int.tryParse(val);
        if (qty == null || qty <= 0) {
          return 'Must be > 0';
        }
        if (!widget.allowUnlimitedQuantity && qty > _maxAllowedStock) {
          return 'Max $_maxAllowedStock';
        }
        return null;
      },
    );
  }

  Widget _buildRateField(String currencySymbol) {
    return TextFormField(
      controller: _rateController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      onChanged: (val) {
        final rate = double.tryParse(val) ?? 0.0;
        context.read<LineEditorCubit>().setRate(rate);
      },
      decoration: _denseDecoration(
        labelText: 'Rate ($currencySymbol)',
        hintText: 'Rate',
      ),
      validator: (val) {
        if (val == null || val.isEmpty) return 'Required';
        final parsedRate = double.tryParse(val);
        if (parsedRate == null || parsedRate <= 0) {
          return 'Must be > 0';
        }
        return null;
      },
    );
  }

  Widget _buildDiscountField(String currencySymbol) {
    return TextFormField(
      controller: _discountController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      onChanged: (val) {
        final discount = double.tryParse(val) ?? 0.0;
        context.read<LineEditorCubit>().setDiscount(discount);
      },
      decoration: _denseDecoration(
        labelText: 'Discount ($currencySymbol)',
        hintText: '0.00',
      ),
      validator: (val) {
        if (val == null || val.isEmpty) {
          return 'Required';
        }
        final parsedDiscount = double.tryParse(val);
        if (parsedDiscount == null || parsedDiscount < 0) {
          return 'Must be ≥ 0';
        }
        final qty = int.tryParse(_quantityController.text) ?? 0;
        final currentRate = double.tryParse(_rateController.text) ?? 0.0;
        if (parsedDiscount > (currentRate * qty)) {
          return 'Exceeds subtotal';
        }
        return null;
      },
    );
  }

  Widget _buildFields({required bool wide, required String currencySymbol}) {
    final qty = _buildQuantityField();
    final rate = _buildRateField(currencySymbol);
    final discount = _buildDiscountField(currencySymbol);

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: qty),
          const SizedBox(width: 8),
          Expanded(child: rate),
          const SizedBox(width: 8),
          Expanded(child: discount),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: qty),
            const SizedBox(width: 8),
            Expanded(child: rate),
          ],
        ),
        const SizedBox(height: 10),
        discount,
      ],
    );
  }

  Widget _buildStockBadge({
    required bool isDark,
    required int displayStock,
  }) {
    return Container(
      width: double.infinity,
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
                '${widget.originalQuantity > 0 ? ' (incl. ${widget.originalQuantity} billed)' : ''}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: displayStock > 0
              ? AppTheme.successEmerald
              : AppTheme.errorRose,
        ),
      ),
    );
  }

  Widget _buildIdentity({
    required bool wide,
    required bool isDark,
    required String currencySymbol,
    required int displayStock,
  }) {
    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.item.name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          'SKU: ${widget.item.sku} · ${formatCurrency(widget.item.rate, currencySymbol)}',
          style: TextStyle(
            fontSize: 12,
            color: isDark
                ? AppTheme.darkTextSecondary
                : AppTheme.lightTextSecondary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    final stock = _buildStockBadge(
      isDark: isDark,
      displayStock: displayStock,
    );

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: nameBlock),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: stock,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        nameBlock,
        const SizedBox(height: 8),
        stock,
      ],
    );
  }

  Widget _buildTotals({
    required bool wide,
    required bool isDark,
    required String currencySymbol,
    required LineEditorState state,
  }) {
    final cells = [
      _TotalCell(
        label: 'Subtotal',
        value: formatCurrency(state.subtotal, currencySymbol),
      ),
      _TotalCell(
        label: 'Discount',
        value: formatCurrency(state.discount, currencySymbol),
        valueColor: AppTheme.errorRose,
      ),
      _TotalCell(
        label: 'VAT (${widget.item.taxPercentage}%)',
        value: formatCurrency(state.taxAmount, currencySymbol),
      ),
      _TotalCell(
        label: 'Total',
        value: formatCurrency(state.total, currencySymbol),
        bold: true,
        valueColor: AppTheme.primaryIndigo,
      ),
    ];

    final grid = wide
        ? Row(
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: cells[i]),
              ],
            ],
          )
        : Column(
            children: [
              Row(
                children: [
                  Expanded(child: cells[0]),
                  const SizedBox(width: 8),
                  Expanded(child: cells[1]),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: cells[2]),
                  const SizedBox(width: 8),
                  Expanded(child: cells[3]),
                ],
              ),
            ],
          );

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: grid,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;
    final media = MediaQuery.of(context);
    final displayStock = widget.allowUnlimitedQuantity
        ? widget.item.stock
        : _maxAllowedStock;

    const horizontalInset = 12.0;
    const verticalInset = 12.0;
    final maxDialogWidth = math.min(
      560.0,
      media.size.width - (horizontalInset * 2),
    );
    final maxDialogHeight = media.size.height -
        media.viewInsets.vertical -
        (verticalInset * 2);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: verticalInset,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxDialogWidth,
          maxHeight: maxDialogHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Form(
            key: _formKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= _kWideLayoutMinWidth;

                final content = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DialogHeader(title: widget.title),
                    _buildIdentity(
                      wide: wide,
                      isDark: isDark,
                      currencySymbol: cs,
                      displayStock: displayStock,
                    ),
                    const SizedBox(height: 12),
                    _buildFields(wide: wide, currencySymbol: cs),
                    const SizedBox(height: 12),
                    BlocBuilder<LineEditorCubit, LineEditorState>(
                      builder: (context, state) {
                        return _buildTotals(
                          wide: wide,
                          isDark: isDark,
                          currencySymbol: cs,
                          state: state,
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    DialogActionButtons(
                      submitLabel:
                          widget.initialQuantity > 0 ? 'Update' : 'Add Item',
                      onSubmit: _submit,
                    ),
                  ],
                );

                // Last-resort fallback only when the viewport (e.g. keyboard)
                // is shorter than the intrinsic content height.
                if (constraints.maxHeight.isFinite &&
                    constraints.maxHeight < 420) {
                  return SingleChildScrollView(
                    child: content,
                  );
                }
                return content;
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TotalCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  const _TotalCell({
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: isDark
                ? AppTheme.darkTextSecondary
                : AppTheme.lightTextSecondary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? 13 : 12,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: valueColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
