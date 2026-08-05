import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/models/item.dart';
import '../theme/app_theme.dart';
import '../extensions/org_context_extension.dart';
import '../utils/currency.dart';
import '../utils/quantity_format.dart';
import '../cubit/line_editor_cubit.dart';
import 'dialog_scaffolding.dart';
import '../../features/dashboard/widgets/item_line_editor_totals.dart';
import '../../features/dashboard/widgets/item_line_uom_selector.dart';

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
/// Result of [SharedItemLineEditorDialog]: quantity, rate, discount, UOM and
/// the Zoho unit_conversion_id of the selected unit ('' for the base unit).
///
/// [quantity] and [rate] are expressed in the selected unit.
typedef ItemLineEditorResult = ({
  double quantity,
  double rate,
  double discount,
  String uom,
  String unitConversionId,
});

class SharedItemLineEditorDialog extends StatelessWidget {
  final Item item;
  final double initialQuantity;

  /// The quantity already billed on the invoice being edited, in the item's
  /// **base unit** (used to widen the stock cap when re-editing a line).
  final double originalQuantity;
  final bool allowUnlimitedQuantity;
  final String title;
  final double? initialRate;
  final double? initialDiscount;
  /// Pre-selected unit of measure (edit mode). Falls back to [Item.uom].
  final String? initialUom;

  const SharedItemLineEditorDialog({
    super.key,
    required this.item,
    this.initialQuantity = 0,
    this.originalQuantity = 0,
    this.allowUnlimitedQuantity = false,
    this.title = 'Line Item Details',
    this.initialRate,
    this.initialDiscount,
    this.initialUom,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveUom = (initialUom?.trim().isNotEmpty ?? false)
        ? initialUom!.trim()
        : item.uom;
    return BlocProvider<LineEditorCubit>(
      create: (_) => LineEditorCubit(
        initialQuantity: initialQuantity,
        initialRate: initialRate ?? item.rateFor(effectiveUom),
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
        initialUom: initialUom,
      ),
    );
  }
}

/// Internal stateful shell — only kept stateful to own the [TextEditingController]s
/// and [GlobalKey<FormState>], which must be widget-local for IME compatibility.
/// All reactive display logic (totals panel) uses [BlocBuilder]; no [setState] is called.
class _LineEditorDialogBody extends StatefulWidget {
  final Item item;
  final double initialQuantity;
  final double originalQuantity;
  final bool allowUnlimitedQuantity;
  final String title;
  final double? initialRate;
  final double? initialDiscount;
  final String? initialUom;

  const _LineEditorDialogBody({
    required this.item,
    required this.initialQuantity,
    required this.originalQuantity,
    required this.allowUnlimitedQuantity,
    required this.title,
    this.initialRate,
    this.initialDiscount,
    this.initialUom,
  });

  @override
  State<_LineEditorDialogBody> createState() => _LineEditorDialogBodyState();
}

class _LineEditorDialogBodyState extends State<_LineEditorDialogBody> {
  late final TextEditingController _quantityController;
  late final TextEditingController _rateController;
  late final TextEditingController _discountController;
  final _formKey = GlobalKey<FormState>();

  /// Whether the item offers more than the base unit — drives whether the unit
  /// dropdown is interactive and how wide its column is.
  bool get _hasUnitOptions => _unitOptions.length > 1;

  /// Currently selected unit. Always one of [_unitOptions], or '' when the item
  /// has no known unit at all.
  late String _selectedUom;

  /// Base-unit multiplier of the selected unit (1.0 for the base unit).
  double get _conversionRate =>
      widget.item.conversionRateFor(_currentUom);

  /// Decimal places allowed for quantities in the selected unit. The base
  /// unit has no Zoho-declared precision — allow up to 3.
  int get _quantityDecimals =>
      widget.item.conversionFor(_currentUom)?.quantityDecimalPlaces ?? 3;

  String get _currentUom => _selectedUom;

  /// Max stock available for this line, in the item's base unit.
  double get _maxAllowedBaseStock =>
      widget.item.stock + widget.originalQuantity;

  /// Max stock expressed in the currently selected unit.
  double get _maxAllowedStock =>
      _conversionRate > 0 ? _maxAllowedBaseStock / _conversionRate : 0;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(
      text: widget.initialQuantity > 0
          ? formatQuantity(widget.initialQuantity)
          : '1',
    );
    final fromLine = widget.initialUom?.trim() ?? '';
    final fromItem = widget.item.uom.trim();
    final initialUom = fromLine.isNotEmpty ? fromLine : fromItem;
    // Guard against a stale line uom that no longer matches any known unit —
    // fall back to the base unit (first option) so the dropdown always shows a
    // real selection. Stays '' only for an item with no known unit at all.
    final options = _unitOptions;
    _selectedUom = options.contains(initialUom)
        ? initialUom
        : (options.isNotEmpty ? options.first : '');
    _rateController = TextEditingController(
      text: (widget.initialRate ?? widget.item.rateFor(_currentUom))
          .toStringAsFixed(2),
    );
    _discountController = TextEditingController(
      text: (widget.initialDiscount ?? 0.0).toStringAsFixed(2),
    );
  }

  /// Base unit first, then every conversion target.
  List<String> get _unitOptions => [
        if (widget.item.uom.trim().isNotEmpty) widget.item.uom.trim(),
        ...widget.item.unitConversions.map((c) => c.targetUnit),
      ];

  /// Handles a dropdown unit switch: auto-fills the rate for the new unit
  /// (base rate × conversion rate — still editable afterwards) and refreshes
  /// the qty cap/decimals.
  void _onUnitSelected(String? unit) {
    if (unit == null || unit == _selectedUom) return;
    setState(() => _selectedUom = unit);
    final newRate = widget.item.rateFor(unit);
    _rateController.text = newRate.toStringAsFixed(2);
    context.read<LineEditorCubit>().setUnit(
          baseRate: widget.item.rate,
          conversionRate: widget.item.conversionRateFor(unit),
        );
    _formKey.currentState?.validate();
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
      final qty = double.tryParse(_quantityController.text) ?? 0;
      final rate = double.tryParse(_rateController.text) ?? widget.item.rate;
      final discount = double.tryParse(_discountController.text) ?? 0.0;
      final result = (
        quantity: qty,
        rate: rate,
        discount: discount,
        uom: _currentUom,
        unitConversionId:
            widget.item.conversionFor(_currentUom)?.unitConversionId ?? '',
      );
      Navigator.pop<ItemLineEditorResult>(context, result);
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
    final uomSuffix = _currentUom.isNotEmpty ? _currentUom : null;
    final decimals = _quantityDecimals;
    return TextFormField(
      controller: _quantityController,
      keyboardType: decimals > 0
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      autofocus: true,
      inputFormatters: [
        decimals > 0
            ? FilteringTextInputFormatter.allow(
                RegExp('^\\d*\\.?\\d{0,$decimals}'),
              )
            : FilteringTextInputFormatter.digitsOnly,
      ],
      onChanged: (val) {
        final qty = double.tryParse(val) ?? 0;
        context.read<LineEditorCubit>().setQuantity(qty);
      },
      decoration: _denseDecoration(
        labelText: 'Quantity',
        hintText: 'Qty',
      ).copyWith(suffixText: uomSuffix),
      validator: (val) {
        if (val == null || val.isEmpty) {
          return 'Required';
        }
        final qty = double.tryParse(val);
        if (qty == null || qty <= 0) {
          return 'Must be > 0';
        }
        if (!widget.allowUnlimitedQuantity && qty > _maxAllowedStock) {
          return 'Max ${formatQuantity(_maxAllowedStock)}';
        }
        return null;
      },
    );
  }

  /// UOM field — always a dropdown of the item's real Zoho units (base unit
  /// first, then every conversion target), so a line can never carry a unit
  /// Zoho doesn't know. Switching re-prices the line. With only the base unit
  /// there is nothing to pick, so the dropdown renders disabled; the same
  /// applies to the rare item Zoho gave no unit at all.
  Widget _buildUomField() {
    final options = _unitOptions;
    return ItemLineUomSelector(
      selectedUom: _selectedUom,
      unitOptions: options,
      hasUnitOptions: _hasUnitOptions,
      onChanged: _hasUnitOptions ? _onUnitSelected : null,
      decoration: _denseDecoration(labelText: 'Unit', hintText: 'Unit'),
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
        final qty = double.tryParse(_quantityController.text) ?? 0;
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
    final uom = _buildUomField();
    final rate = _buildRateField(currencySymbol);
    final discount = _buildDiscountField(currencySymbol);

    // Dropdown unit names ("25 Kg Bag") need more room than a short uom tag.
    final uomFlex = _hasUnitOptions ? 2 : 1;

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: qty),
          const SizedBox(width: 8),
          Expanded(flex: uomFlex, child: uom),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: rate),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: discount),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: qty),
            const SizedBox(width: 8),
            Expanded(flex: uomFlex, child: uom),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: rate),
            const SizedBox(width: 8),
            Expanded(child: discount),
          ],
        ),
      ],
    );
  }

  Widget _buildStockBadge({
    required bool isDark,
    required double displayStock,
  }) {
    final baseUom = widget.item.uom.trim();
    final stockText = formatQuantity(displayStock);
    // When an alternate unit is selected, also show the converted capacity
    // (e.g. "Available in Van: 500 kg ≈ 20 25 Kg Bag").
    final converted = _hasUnitOptions &&
            _currentUom != baseUom &&
            _conversionRate > 0
        ? ' ≈ ${formatQuantity(displayStock / _conversionRate)} $_currentUom'
        : '';
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
            ? 'Available in Van: $stockText ${baseUom.isNotEmpty ? baseUom : 'items'}$converted'
            : 'Available in Van: $stockText ${baseUom.isNotEmpty ? baseUom : 'items'}$converted'
                '${widget.originalQuantity > 0 ? ' (incl. ${formatQuantity(widget.originalQuantity)} billed)' : ''}',
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
    required double displayStock,
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
          [
            'SKU: ${widget.item.sku}',
            if (widget.item.uom.isNotEmpty) 'UOM: ${widget.item.uom}',
            formatCurrency(widget.item.rate, currencySymbol),
          ].join(' · '),
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
    return ItemLineEditorTotals(
      wide: wide,
      isDark: isDark,
      currencySymbol: currencySymbol,
      taxPercentage: widget.item.taxPercentage,
      state: state,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;
    final size = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final displayStock = widget.allowUnlimitedQuantity
        ? widget.item.stock
        : _maxAllowedBaseStock;

    const horizontalInset = 12.0;
    const verticalInset = 12.0;
    final maxDialogWidth = math.min(
      560.0,
      size.width - (horizontalInset * 2),
    );
    final maxDialogHeight = size.height -
        viewInsets.vertical -
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


