import 'package:flutter/material.dart';
import '../../../../domain/models/customer.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import 'van_action_tile.dart';

/// Draggable bottom drawer displaying customer-specific operations/actions.
class ClientOperationsSheet extends StatelessWidget {
  final Customer customer;
  final bool isDark;
  final VoidCallback onNewInvoiceTap;
  final VoidCallback onNewOrderTap;
  final VoidCallback onReceiptPaymentTap;
  final VoidCallback onSalesReturnTap;

  const ClientOperationsSheet({
    super.key,
    required this.customer,
    required this.isDark,
    required this.onNewInvoiceTap,
    required this.onNewOrderTap,
    required this.onReceiptPaymentTap,
    required this.onSalesReturnTap,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        final cs = context.org.currencySymbol;
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Text(
                customer.name,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              Text(
                customer.companyName,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'Outstanding: $cs${customer.outstandingBalance.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: customer.outstandingBalance > 0 ? AppTheme.errorRose : AppTheme.successEmerald,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Limit: $cs${customer.creditLimit.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              const Divider(height: 32, color: Color(0xFF334155)),

              VanActionTile(
                title: 'New Sales Invoice',
                subtitle: 'Create cart, calculate taxes, deduct stock, and sync invoice.',
                icon: Icons.description_rounded,
                color: AppTheme.primaryIndigo,
                isDark: isDark,
                onTap: onNewInvoiceTap,
              ),
              const SizedBox(height: 14),
              VanActionTile(
                title: 'New Sales Order',
                subtitle: 'Create offline sales order and enqueue for Zoho sync.',
                icon: Icons.assignment_rounded,
                color: AppTheme.primaryIndigo,
                isDark: isDark,
                onTap: onNewOrderTap,
              ),
              const SizedBox(height: 14),
              VanActionTile(
                title: 'Receipt Voucher (Payment)',
                subtitle: 'Collect payment against outstanding contact balances.',
                icon: Icons.receipt_long_rounded,
                color: AppTheme.successEmerald,
                isDark: isDark,
                onTap: onReceiptPaymentTap,
              ),
              const SizedBox(height: 14),
              VanActionTile(
                title: 'Sales Return (Credit Note)',
                subtitle: 'Record returned stock and restore it back into the van.',
                icon: Icons.assignment_return_rounded,
                color: AppTheme.errorRose,
                isDark: isDark,
                onTap: onSalesReturnTap,
              ),
            ],
          ),
        );
      },
    );
  }
}
