import 'package:flutter/material.dart';

import '../../../../domain/models/customer.dart';
import '../../../../domain/models/sales_order.dart';
import '../../../../domain/repositories/voucher_pdf_repository.dart';
import '../../voucher_pdf/widgets/voucher_pdf_actions_widget.dart';
import '../bloc/sales_order_editor_state.dart';
import 'sales_order_convert_action.dart';

/// Footer trailing column: convert action + voucher PDF actions.
class SalesOrderEditorTrailing extends StatelessWidget {
  final SalesOrderEditorState state;
  final Customer? customer;
  final DateTime orderDate;
  final String notes;

  const SalesOrderEditorTrailing({
    super.key,
    required this.state,
    required this.customer,
    required this.orderDate,
    required this.notes,
  });

  @override
  Widget build(BuildContext context) {
    final savedOrder = state.editingOrder ??
        SalesOrder(
          id: state.editingOrderId ?? '',
          orderNumber: 'SO-TEMP',
          customerId: customer?.id ?? '',
          customerName: customer?.name ?? '',
          date: orderDate,
          shipmentDate:
              state.editingDate?.add(const Duration(days: 7)) ?? DateTime.now(),
          items: state.editingItems,
          notes: notes,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SalesOrderConvertAction(order: savedOrder),
        const SizedBox(height: 16),
        VoucherPdfActionsWidget(
          type: VoucherType.salesOrder,
          voucher: SalesOrder(
            id: state.editingOrderId ?? '',
            orderNumber: savedOrder.orderNumber,
            customerId: customer?.id ?? '',
            customerName: customer?.name ?? '',
            date: orderDate,
            shipmentDate: savedOrder.shipmentDate,
            items: state.editingItems,
            notes: notes,
            status: savedOrder.status,
            convertedInvoiceNumber: savedOrder.convertedInvoiceNumber,
          ),
        ),
      ],
    );
  }
}
