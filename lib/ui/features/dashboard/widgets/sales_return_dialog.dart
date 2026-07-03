import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/models/sales_return_model.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/sync_worker.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/utils/snackbars.dart';

/// Modal dialog for logging a [SalesReturn] credit note.
///
/// Prompts selection of a returned item from the active warehouse product catalog
/// and inputting the returned quantity. Prepares a sales return payload, updates
/// client credit balance or stock in local cache, and enqueues a sync job to post to Zoho.
class SalesReturnDialog extends StatefulWidget {
  /// The selected customer profile returning inventory.
  final Customer customer;

  /// Callback triggered when the sales return transaction is successfully processed and cached.
  final VoidCallback onReturnConfirmed;

  /// Creates a new [SalesReturnDialog] widget.
  const SalesReturnDialog({
    super.key,
    required this.customer,
    required this.onReturnConfirmed,
  });

  @override
  State<SalesReturnDialog> createState() => _SalesReturnDialogState();
}

class _SalesReturnDialogState extends State<SalesReturnDialog> {
  final HiveDatabaseService _db = sl<HiveDatabaseService>();
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  final _formKey = GlobalKey<FormState>();

  late List<Item> _items;
  Item? _selectedItem;
  List<SalesInvoice> _matchingInvoices = [];
  final Map<String, TextEditingController> _qtyControllers = {};

  @override
  void initState() {
    super.initState();
    // Get all local invoices for this customer
    final invoices = _db.getLocalInvoices()
        .where((inv) => inv.customerId == widget.customer.id)
        .toList();
    // Get all unique item IDs from these invoices
    final purchasedItemIds = invoices
        .expand((inv) => inv.items)
        .map((line) => line.item.id)
        .toSet();

    _items = _db.getItems()
        .where((item) => purchasedItemIds.contains(item.id))
        .toList();
  }

  @override
  void dispose() {
    for (final controller in _qtyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onItemChanged(Item? val) {
    if (val == null) return;
    setState(() {
      _selectedItem = val;
      
      // Clear existing controllers
      for (final controller in _qtyControllers.values) {
        controller.dispose();
      }
      _qtyControllers.clear();

      // Find matching invoices
      final customerInvoices = _db.getLocalInvoices()
          .where((inv) => inv.customerId == widget.customer.id)
          .toList();
      
      _matchingInvoices = customerInvoices.where((inv) {
        return inv.items.any((line) => line.item.id == val.id);
      }).toList();

      // Sort descending by date
      _matchingInvoices.sort((a, b) => b.date.compareTo(a.date));

      // Create new controllers
      for (final inv in _matchingInvoices) {
        _qtyControllers[inv.id] = TextEditingController();
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedItem == null) return;

    final List<SalesReturnLineItem> returnedLines = [];
    var totalQty = 0;

    for (final inv in _matchingInvoices) {
      final text = _qtyControllers[inv.id]?.text ?? '';
      final qty = int.tryParse(text) ?? 0;

      if (qty > 0) {
        totalQty += qty;
        final originalLine = inv.items.firstWhere((line) => line.item.id == _selectedItem!.id);
        
        returnedLines.add(SalesReturnLineItem(
          invoiceLineItem: originalLine,
          returnedQuantity: qty,
          invoiceId: inv.id,
          invoiceNumber: inv.invoiceNumber,
        ));
      }
    }

    if (totalQty <= 0) {
      showErrorSnackBar(context, 'Please enter return quantity for at least one invoice.');
      return;
    }

    final tempId = 'temp_ret_${DateTime.now().millisecondsSinceEpoch}';
    final returnItem = SalesReturn(
      id: tempId,
      creditNoteNumber: 'RET-TEMP-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
      customerId: widget.customer.id,
      customerName: widget.customer.name,
      date: DateTime.now(),
      items: returnedLines,
      reason: 'Damaged packaging',
      isPendingSync: true,
    );

    // Save local & restore stock instantly!
    await _db.saveLocalReturn(returnItem);

    // Queue Sync
    final syncItem = SyncQueueItem(
      id: tempId,
      type: 'return',
      payload: SalesReturnModel.fromDomain(returnItem).toJson(),
      status: SyncStatus.pending,
      timestamp: DateTime.now(),
    );
    await _db.enqueueSyncItem(syncItem);

    if (!mounted) return;

    sl<SyncWorker>().syncPendingItems();

    Navigator.pop(context);
    showSuccessSnackBar(context, 'Sales Return credit queued. ${_selectedItem!.name} stock restored!');
    widget.onReturnConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: const Text('New Sales Return'),
      content: SizedBox(
        width: 450,
        child: _items.isEmpty
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppTheme.errorRose,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This customer has no purchase history. Returns are only allowed for items sold in previous sales invoices.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    ),
                  ),
                ],
              )
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Select returned item and allocate quantity from invoices.'),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<Item>(
                        initialValue: _selectedItem,
                        decoration: const InputDecoration(labelText: 'Returned Item'),
                        items: _items
                            .map((item) => DropdownMenuItem(value: item, child: Text(item.name)))
                            .toList(),
                        onChanged: _onItemChanged,
                      ),
                      if (_selectedItem != null) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Select Invoices & Quantities',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        ..._matchingInvoices.map((inv) {
                          final originalLine = inv.items.firstWhere((line) => line.item.id == _selectedItem!.id);
                          final maxQty = originalLine.quantity;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
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
                                            fontSize: 13,
                                            color: AppTheme.warningAmber,
                                          ),
                                        ),
                                        Text(
                                          'Date: ${_dateFormat.format(inv.date)}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                          ),
                                        ),
                                        Text(
                                          'Sold: $maxQty units',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 80,
                                    child: TextFormField(
                                      controller: _qtyControllers[inv.id],
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                      decoration: InputDecoration(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        hintText: '0',
                                        isDense: true,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      textAlign: TextAlign.center,
                                      validator: (val) {
                                        if (val == null || val.isEmpty) return null;
                                        final qty = int.tryParse(val);
                                        if (qty == null) return 'Invalid';
                                        if (qty < 0) return 'Min 0';
                                        if (qty > maxQty) return 'Max $maxQty';
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        ElevatedButton(
          onPressed: _items.isEmpty || _selectedItem == null ? null : _submit,
          child: const Text('CONFIRM RETURN'),
        ),
      ],
    );
  }
}
