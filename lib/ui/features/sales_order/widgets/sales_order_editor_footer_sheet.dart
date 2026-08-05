import 'package:flutter/material.dart';

import '../../../../domain/models/customer.dart';
import '../../../../domain/models/sales_order.dart';
import '../../../../domain/repositories/voucher_pdf_repository.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../voucher_pdf/widgets/voucher_pdf_actions_widget.dart';
import '../bloc/sales_order_editor_state.dart';
import 'sales_order_convert_action.dart';

/// Bottom [DraggableScrollableSheet] for the sales-order editor.
///
/// Collapsed: drag handle + grand total + primary action (Save / Close).
/// Expanded: full totals breakdown + congregated document actions
/// (convert + PDF/thermal/share) so re-opened orders do not bury the form.
class SalesOrderEditorFooterSheet extends StatelessWidget {
  final List<({String label, String value, bool emphasize})> rows;
  final String buttonLabel;
  final VoidCallback? onSave;
  final bool showDocumentActions;
  final SalesOrderEditorState state;
  final Customer? customer;
  final DateTime orderDate;
  final String notes;

  const SalesOrderEditorFooterSheet({
    super.key,
    required this.rows,
    required this.buttonLabel,
    required this.onSave,
    required this.showDocumentActions,
    required this.state,
    required this.customer,
    required this.orderDate,
    required this.notes,
  });

  SalesOrder _voucherOrder() {
    final saved = state.editingOrder;
    return SalesOrder(
      id: state.editingOrderId ?? saved?.id ?? '',
      orderNumber: saved?.orderNumber ?? 'SO-TEMP',
      customerId: customer?.id ?? saved?.customerId ?? '',
      customerName: customer?.name ?? saved?.customerName ?? '',
      date: orderDate,
      shipmentDate: saved?.shipmentDate ??
          orderDate.add(const Duration(days: 7)),
      items: state.editingItems,
      notes: notes,
      status: saved?.status ?? SalesOrderStatus.open,
      convertedInvoiceNumber: saved?.convertedInvoiceNumber,
      zohoOrderId: saved?.zohoOrderId,
      orderStatus: saved?.orderStatus ?? '',
      invoicedStatus: saved?.invoicedStatus ?? '',
      referenceNumber: saved?.referenceNumber ?? '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    ({String label, String value, bool emphasize})? totalRow;
    for (final r in rows) {
      if (r.emphasize) totalRow = r;
    }
    final detailRows = rows.where((r) => !r.emphasize).toList();
    final maxSize = showDocumentActions ? 0.55 : 0.36;

    return DraggableScrollableSheet(
      initialChildSize: 0.17,
      minChildSize: 0.15,
      maxChildSize: maxSize,
      expand: true,
      snap: true,
      snapSizes: showDocumentActions
          ? const [0.17, 0.36, 0.55]
          : const [0.17, 0.36],
      builder: (context, scrollController) {
        return Material(
          color: surface,
          elevation: 12,
          shadowColor: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(top: BorderSide(color: border)),
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                // Always-visible compact bar: total + primary CTA.
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            totalRow?.label ?? 'Total',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
                          Text(
                            totalRow?.value ?? '—',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: AppTheme.primaryIndigo,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: onSave,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryIndigo,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                      ),
                      child: Text(buttonLabel),
                    ),
                  ],
                ),
                if (detailRows.isNotEmpty || showDocumentActions) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.keyboard_arrow_up_rounded,
                        size: 18,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Swipe up for details'
                        '${showDocumentActions ? ' & actions' : ''}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
                if (detailRows.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  for (final row in detailRows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            row.label,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
                          Text(row.value),
                        ],
                      ),
                    ),
                ],
                if (showDocumentActions) ...[
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Text(
                    'Document actions',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SalesOrderConvertAction(
                    order: _voucherOrder(),
                    compact: true,
                  ),
                  const SizedBox(height: 10),
                  VoucherPdfActionsWidget(
                    type: VoucherType.salesOrder,
                    voucher: _voucherOrder(),
                    compact: true,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
