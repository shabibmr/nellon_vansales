import 'package:flutter/material.dart';

import '../../../../domain/models/customer.dart';
import '../../../../ui/core/theme/app_theme.dart';

/// Customer selector/display card used on the sales order editor.
class SalesOrderCustomerCard extends StatelessWidget {
  final Customer? customer;

  /// When true the card is tappable (new order only).
  final bool canSelect;
  final VoidCallback? onTap;

  const SalesOrderCustomerCard({
    super.key,
    required this.customer,
    required this.canSelect,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;

    return Card(
      child: InkWell(
        onTap: canSelect ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    AppTheme.primaryIndigo.withValues(alpha: 0.1),
                child: const Icon(
                  Icons.person,
                  color: AppTheme.primaryIndigo,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CUSTOMER',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: secondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      customer?.name ?? 'Select Customer',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (customer != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        customer!.companyName,
                        style: TextStyle(
                          fontSize: 12,
                          color: secondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (canSelect)
                Icon(Icons.keyboard_arrow_right, color: secondary),
            ],
          ),
        ),
      ),
    );
  }
}
