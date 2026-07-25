import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/utils/quantity_format.dart';

/// Modal dialog for choosing sales invoices containing the selected item,
/// and entering return quantities allocated against those invoices.
class ReturnInvoiceSelectorDialog extends StatefulWidget {
  final Customer customer;
  final Item item;
  final List<SalesReturnLineItem> currentLines;

  const ReturnInvoiceSelectorDialog({
    super.key,
    required this.customer,
    required this.item,
    required this.currentLines,
  });

  @override
  State<ReturnInvoiceSelectorDialog> createState() =>
      _ReturnInvoiceSelectorDialogState();
}

class _ReturnInvoiceSelectorDialogState
    extends State<ReturnInvoiceSelectorDialog> {
  final HiveDatabaseService _db = sl<HiveDatabaseService>();
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  final _formKey = GlobalKey<FormState>();

  late List<SalesInvoice> _matchingInvoices;
  final Map<String, TextEditingController> _qtyControllers = {};

  /// Per-invoice unit the return quantity is entered in.
  final Map<String, String> _selectedUoms = {};

  /// The item carrying unit_conversions — prefer the fresh master item; fall
  /// back to the snapshot embedded in the invoice line.
  Item _conversionSource(InvoiceLineItem originalLine) =>
      widget.item.unitConversions.isNotEmpty ? widget.item : originalLine.item;

  /// Unit options for a return against [originalLine]: base unit + alternates.
  List<String> _unitOptions(InvoiceLineItem originalLine) {
    final source = _conversionSource(originalLine);
    return [
      if (source.uom.trim().isNotEmpty) source.uom.trim(),
      ...source.unitConversions.map((c) => c.targetUnit),
    ];
  }

  /// Max returnable in [selectedUom]: sold base-unit quantity ÷ the selected
  /// unit's conversion rate.
  double _maxReturnable(InvoiceLineItem originalLine, String selectedUom) {
    final source = _conversionSource(originalLine);
    final rate = source.conversionRateFor(selectedUom);
    if (rate <= 0) return originalLine.quantityInBase;
    return originalLine.quantityInBase / rate;
  }

  int _decimalsFor(InvoiceLineItem originalLine, String selectedUom) =>
      _conversionSource(originalLine)
          .conversionFor(selectedUom)
          ?.quantityDecimalPlaces ??
      3;

  @override
  void initState() {
    super.initState();
    // Get all local invoices for the customer containing the selected item
    final customerInvoices = _db
        .getLocalInvoices()
        .where((inv) => inv.customerId == widget.customer.id)
        .toList();

    _matchingInvoices = customerInvoices.where((inv) {
      return inv.items.any((line) => line.item.id == widget.item.id);
    }).toList();

    // Sort descending by voucher date
    _matchingInvoices.sort((a, b) => b.date.compareTo(a.date));

    // Initialize controllers with current returns if any
    for (final inv in _matchingInvoices) {
      SalesReturnLineItem? existingLine;
      for (final line in widget.currentLines) {
        if (line.invoiceId == inv.id &&
            line.invoiceLineItem.item.id == widget.item.id) {
          existingLine = line;
          break;
        }
      }

      final initialQty = existingLine?.returnedQuantity ?? 0;
      _qtyControllers[inv.id] = TextEditingController(
        text: initialQty > 0 ? formatQuantity(initialQty) : '',
      );

      // Default unit: the existing return line's unit, else the sold unit.
      final originalLine = inv.items.firstWhere(
        (line) => line.item.id == widget.item.id,
      );
      final defaultUom = existingLine?.displayUom ?? originalLine.displayUom;
      final options = _unitOptions(originalLine);
      _selectedUoms[inv.id] = options.contains(defaultUom)
          ? defaultUom
          : (options.isNotEmpty ? options.first : defaultUom);
    }
  }

  @override
  void dispose() {
    for (final controller in _qtyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final List<SalesReturnLineItem> returnedLines = [];

      for (final inv in _matchingInvoices) {
        final text = _qtyControllers[inv.id]?.text ?? '';
        final qty = double.tryParse(text) ?? 0;

        if (qty > 0) {
          // Find original invoice line item
          final originalLine = inv.items.firstWhere(
            (line) => line.item.id == widget.item.id,
          );
          final selUom = _selectedUoms[inv.id] ?? originalLine.displayUom;
          final conversion =
              _conversionSource(originalLine).conversionFor(selUom);

          returnedLines.add(
            SalesReturnLineItem(
              invoiceLineItem: originalLine,
              returnedQuantity: qty,
              invoiceId: inv.id,
              invoiceNumber: inv.invoiceNumber,
              uom: selUom,
              unitConversionId: conversion?.unitConversionId ?? '',
            ),
          );
        }
      }

      Navigator.pop(context, returnedLines);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
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
                    'Select Invoices & Qty',
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
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'SKU: ${widget.item.sku} | Rate: $cs${widget.item.rate.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 16),
              if (_matchingInvoices.isEmpty)
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 48,
                          color: AppTheme.errorRose,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'No sales invoices found containing this item for this customer.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.errorRose,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _matchingInvoices.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final inv = _matchingInvoices[index];
                      final originalLine = inv.items.firstWhere(
                        (line) => line.item.id == widget.item.id,
                      );
                      final unitOptions = _unitOptions(originalLine);
                      final selUom =
                          _selectedUoms[inv.id] ?? originalLine.displayUom;
                      final maxQty = _maxReturnable(originalLine, selUom);
                      final decimals = _decimalsFor(originalLine, selUom);

                      return Card(
                        margin: EdgeInsets.zero,
                        color: isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF8FAFC),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 12.0,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      inv.invoiceNumber,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: AppTheme.warningAmber,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Date: ${_dateFormat.format(inv.date)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? AppTheme.darkTextSecondary
                                            : AppTheme.lightTextSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Sold: ${formatQuantity(originalLine.quantity)} ${originalLine.displayUom}'
                                      ' @ $cs${originalLine.rate.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? AppTheme.darkText
                                            : AppTheme.lightText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Unit selector — return can be in any of the
                              // item's units; the qty cap converts from the
                              // sold quantity.
                              if (unitOptions.length > 1)
                                SizedBox(
                                  width: 110,
                                  child: DropdownButtonFormField<String>(
                                    key: ValueKey('ret_uom_${inv.id}_$selUom'),
                                    initialValue:
                                        unitOptions.contains(selUom)
                                            ? selUom
                                            : null,
                                    isExpanded: true,
                                    isDense: true,
                                    decoration: InputDecoration(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 8,
                                      ),
                                      isDense: true,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? AppTheme.darkText
                                          : AppTheme.lightText,
                                    ),
                                    items: unitOptions
                                        .map(
                                          (u) => DropdownMenuItem<String>(
                                            value: u,
                                            child: Text(
                                              u,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (u) {
                                      if (u == null) return;
                                      setState(
                                        () => _selectedUoms[inv.id] = u,
                                      );
                                      _formKey.currentState?.validate();
                                    },
                                  ),
                                ),
                              if (unitOptions.length > 1)
                                const SizedBox(width: 8),
                              SizedBox(
                                width: 80,
                                child: TextFormField(
                                  controller: _qtyControllers[inv.id],
                                  keyboardType: decimals > 0
                                      ? const TextInputType.numberWithOptions(
                                          decimal: true,
                                        )
                                      : TextInputType.number,
                                  inputFormatters: [
                                    decimals > 0
                                        ? FilteringTextInputFormatter.allow(
                                            RegExp(
                                              '^\\d*\\.?\\d{0,$decimals}',
                                            ),
                                          )
                                        : FilteringTextInputFormatter
                                            .digitsOnly,
                                  ],
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    hintText: '0',
                                    isDense: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  textAlign: TextAlign.center,
                                  validator: (val) {
                                    if (val == null || val.isEmpty) return null;
                                    final qty = double.tryParse(val);
                                    if (qty == null) return 'Invalid';
                                    if (qty < 0) return 'Min 0';
                                    if (qty > maxQty) {
                                      return 'Max ${formatQuantity(maxQty)}';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _matchingInvoices.isEmpty ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.warningAmber,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Confirm'),
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
