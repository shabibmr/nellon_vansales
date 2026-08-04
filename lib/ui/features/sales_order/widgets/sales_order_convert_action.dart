import 'package:flutter/material.dart';

import '../../../../domain/models/sales_order.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../sales_invoice/views/sales_invoice_editor_page.dart';

/// "Convert to Invoice" button or converted status indicator.
class SalesOrderConvertAction extends StatelessWidget {
  final SalesOrder order;

  const SalesOrderConvertAction({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    if (order.isConverted) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.check_circle,
            color: AppTheme.successEmerald,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            order.convertedInvoiceNumber != null
                ? 'Converted to ${order.convertedInvoiceNumber}'
                : 'Converted to invoice',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.receipt_long),
        label: const Text('CONVERT TO INVOICE'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primaryIndigo,
          side: const BorderSide(color: AppTheme.primaryIndigo),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: () {
          SalesInvoiceEditorPage.open(context, fromOrder: order);
        },
      ),
    );
  }
}
