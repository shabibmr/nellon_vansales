import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../bloc/customer_ledger_bloc.dart';

class LedgerFilterHeader extends StatelessWidget {
  final CustomerLedgerState state;
  final bool isDark;
  final DateFormat dateFormat;
  final VoidCallback onSelectCustomer;
  final VoidCallback onPickStartDate;
  final VoidCallback onPickEndDate;
  final VoidCallback onFetch;

  const LedgerFilterHeader({
    super.key,
    required this.state,
    required this.isDark,
    required this.dateFormat,
    required this.onSelectCustomer,
    required this.onPickStartDate,
    required this.onPickEndDate,
    required this.onFetch,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: isDark ? 0 : 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Customer selector
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onSelectCustomer,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                    ),
                    borderRadius: BorderRadius.circular(10),
                    color: isDark
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFF8FAFC),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.person_search_outlined,
                        color: AppTheme.primaryIndigo,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.selectedCustomer?.name ?? 'Select Customer',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: state.selectedCustomer != null
                                    ? (isDark
                                          ? AppTheme.darkText
                                          : AppTheme.lightText)
                                    : (isDark
                                          ? AppTheme.darkTextSecondary
                                          : AppTheme.lightTextSecondary),
                              ),
                            ),
                            if (state.selectedCustomer != null &&
                                state.selectedCustomer!.companyName.isNotEmpty)
                              Text(
                                state.selectedCustomer!.companyName,
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
                      Icon(
                        Icons.arrow_drop_down,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Date range
              Row(
                children: [
                  Expanded(
                    child: _DateBox(
                      isDark: isDark,
                      label: dateFormat.format(state.startDate),
                      icon: Icons.date_range,
                      onTap: onPickStartDate,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('to', style: TextStyle(fontSize: 12)),
                  ),
                  Expanded(
                    child: _DateBox(
                      isDark: isDark,
                      label: dateFormat.format(state.endDate),
                      icon: Icons.date_range,
                      onTap: onPickEndDate,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Fetch button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: state.canFetch ? onFetch : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryIndigo,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: state.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.cloud_download_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                  label: Text(
                    state.isLoading
                        ? 'Fetching from Zoho...'
                        : 'Fetch Ledger Report',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  final bool isDark;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _DateBox({
    required this.isDark,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
          borderRadius: BorderRadius.circular(8),
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppTheme.primaryIndigo),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppTheme.darkText : AppTheme.lightText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
