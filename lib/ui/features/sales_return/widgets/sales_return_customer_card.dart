import 'package:flutter/material.dart';

import '../../../../domain/models/customer.dart';
import '../../../core/theme/app_theme.dart';

class SalesReturnCustomerCard extends StatelessWidget {
  final Customer? customer;
  final bool canSelect;
  final VoidCallback onTap;

  const SalesReturnCustomerCard({
    super.key,
    required this.customer,
    required this.canSelect,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: canSelect ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.warningAmber.withValues(alpha: 0.1),
                child: const Icon(
                  Icons.person_outline,
                  color: AppTheme.warningAmber,
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
                        letterSpacing: 1,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      customer?.name ?? 'Select Customer',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: customer == null
                            ? (isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.lightTextSecondary)
                            : null,
                      ),
                    ),
                    if (customer?.companyName.isNotEmpty ?? false)
                      Text(
                        customer!.companyName,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (canSelect)
                const Icon(
                  Icons.chevron_right,
                  color: AppTheme.warningAmber,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
