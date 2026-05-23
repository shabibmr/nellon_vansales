import 'package:flutter/material.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/sync_worker.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/theme/app_theme.dart';

class SalesReturnDialog extends StatefulWidget {
  final Customer customer;
  final VoidCallback onReturnConfirmed;

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
  late List<Item> _items;
  Item? _selectedItem;
  final _qtyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _items = _db.getItems();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Sales Return'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select returned item and quantity to credit.'),
            const SizedBox(height: 16),
            // ignore: deprecated_member_use
            DropdownButtonFormField<Item>(
              value: _selectedItem,
              decoration: const InputDecoration(labelText: 'Returned Item'),
              items: _items
                  .map((item) => DropdownMenuItem(value: item, child: Text(item.name)))
                  .toList(),
              onChanged: (val) {
                setState(() {
                  _selectedItem = val;
                });
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Returned Quantity'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        ElevatedButton(
          onPressed: () async {
            final qty = int.tryParse(_qtyController.text.trim()) ?? 0;
            if (_selectedItem == null || qty <= 0) return;

            final tempId = 'temp_ret_${DateTime.now().millisecondsSinceEpoch}';
            final lineItem = InvoiceLineItem(
              item: _selectedItem!,
              quantity: qty,
              rate: _selectedItem!.rate,
              taxPercentage: _selectedItem!.taxPercentage,
            );

            final returnItem = SalesReturn(
              id: tempId,
              creditNoteNumber: 'RET-TEMP-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
              customerId: widget.customer.id,
              customerName: widget.customer.name,
              date: DateTime.now(),
              items: [SalesReturnLineItem(invoiceLineItem: lineItem, returnedQuantity: qty)],
              reason: 'Damaged packaging',
              isPendingSync: true,
            );

            // Save local & restore stock instantly!
            await _db.saveLocalReturn(returnItem);

            // Queue Sync
            final syncItem = SyncQueueItem(
              id: tempId,
              type: 'return',
              payload: {
                'creditnote_id': tempId,
                'customer_id': widget.customer.id,
                'date': returnItem.date.toIso8601String().split('T')[0],
                'line_items': [
                  {
                    'item_id': _selectedItem!.id,
                    'quantity': qty,
                    'rate': _selectedItem!.rate,
                  }
                ],
                'reason': returnItem.reason,
                'isPendingSync': true,
              },
              status: SyncStatus.pending,
              timestamp: DateTime.now(),
            );
            await _db.enqueueSyncItem(syncItem);

            if (!context.mounted) return;

            sl<SyncWorker>().syncPendingItems();

            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppTheme.successEmerald,
                content: Text('Sales Return credit queued. ${_selectedItem!.name} stock restored!'),
              ),
            );
            widget.onReturnConfirmed();
          },
          child: const Text('CONFIRM RETURN'),
        ),
      ],
    );
  }
}
