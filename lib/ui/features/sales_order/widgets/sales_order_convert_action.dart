import 'package:flutter/material.dart';

import '../../../../domain/models/sales_order.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../sales_invoice/views/sales_invoice_editor_page.dart';

/// "Convert to Invoice" button or converted status indicator.
class SalesOrderConvertAction extends StatelessWidget {
  final SalesOrder order;

  /// Dense single-row layout for the editor footer sheet.
  final bool compact;

  const SalesOrderConvertAction({
    super.key,
    required this.order,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (order.isConverted) {
      return Row(
        children: [
          const Icon(
            Icons.check_circle,
            color: AppTheme.successEmerald,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              order.convertedInvoiceNumber != null
                  ? 'Converted to ${order.convertedInvoiceNumber}'
                  : 'Converted to invoice',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: compact ? 13 : 14,
              ),
            ),
          ),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: Icon(Icons.receipt_long, size: compact ? 18 : 20),
        label: Text(compact ? 'Convert to invoice' : 'CONVERT TO INVOICE'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primaryIndigo,
          side: const BorderSide(color: AppTheme.primaryIndigo),
          padding: EdgeInsets.symmetric(vertical: compact ? 10 : 14),
          visualDensity:
              compact ? VisualDensity.compact : VisualDensity.standard,
        ),
        onPressed: () {
          SalesInvoiceEditorPage.open(context, fromOrder: order);
        },
      ),
    );
  }
}
