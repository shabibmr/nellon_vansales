import 'package:flutter/material.dart';

import '../../../../domain/models/receipt_voucher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';

class ReceiptAllocationsSection extends StatelessWidget {
  final List<PaymentAllocation> allocations;
  final String currencySymbol;
  final bool readOnly;
  final VoidCallback? onManageAllocations;

  const ReceiptAllocationsSection({
    super.key,
    required this.allocations,
    required this.currencySymbol,
    required this.readOnly,
    this.onManageAllocations,
  });

  @override
  Widget build(BuildContext context) {
    final totalAllocated = allocations.fold(0.0, (sum, a) => sum + a.amountApplied);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'INVOICE ALLOCATIONS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            if (!readOnly && onManageAllocations != null)
              TextButton.icon(
                onPressed: onManageAllocations,
                icon: const Icon(Icons.edit_note, size: 18),
                label: const Text('MANAGE'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (allocations.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  'No invoices allocated — payment recorded as unapplied balance.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  ...allocations.map((alloc) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            alloc.invoiceNumber,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            formatCurrency(alloc.amountApplied, currencySymbol),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.successEmerald,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Allocated:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        formatCurrency(totalAllocated, currencySymbol),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.successEmerald,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
