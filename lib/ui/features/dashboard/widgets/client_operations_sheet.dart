import 'package:flutter/material.dart';
import '../../../../domain/models/customer.dart';
import '../../../../ui/core/theme/app_theme.dart';

class ClientOperationsSheet extends StatelessWidget {
  final Customer customer;
  final bool isDark;
  final VoidCallback onNewInvoiceTap;
  final VoidCallback onReceiptPaymentTap;
  final VoidCallback onSalesReturnTap;

  const ClientOperationsSheet({
    super.key,
    required this.customer,
    required this.isDark,
    required this.onNewInvoiceTap,
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
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Indicator handle
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

              // Client Summary Header
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Outstanding: ₹${customer.outstandingBalance.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: customer.outstandingBalance > 0 ? AppTheme.errorRose : AppTheme.successEmerald,
                    ),
                  ),
                  Text(
                    'Credit Limit: ₹${customer.creditLimit.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const Divider(height: 32, color: Color(0xFF334155)),

              // List of Agent Operations
              _buildOperationItem(
                title: 'New Sales Invoice',
                subtitle: 'Create cart, calculate taxes, deduct stock, and sync invoice.',
                icon: Icons.description_rounded,
                color: AppTheme.primaryIndigo,
                onTap: onNewInvoiceTap,
              ),
              const SizedBox(height: 14),
              _buildOperationItem(
                title: 'Receipt Voucher (Payment)',
                subtitle: 'Collect payment against outstanding contact balances.',
                icon: Icons.receipt_long_rounded,
                color: AppTheme.successEmerald,
                onTap: onReceiptPaymentTap,
              ),
              const SizedBox(height: 14),
              _buildOperationItem(
                title: 'Sales Return (Credit Note)',
                subtitle: 'Record returned stock and restore it back into the van.',
                icon: Icons.assignment_return_rounded,
                color: AppTheme.errorRose,
                onTap: onSalesReturnTap,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOperationItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, height: 1.3),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14),
          ],
        ),
      ),
    );
  }
}
