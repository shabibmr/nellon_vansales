import 'package:flutter/material.dart';
import '../../../domain/models/customer.dart';
import '../theme/app_theme.dart';
import '../extensions/org_context_extension.dart';
import '../utils/currency.dart';

/// Generic customer-selector bottom sheet shared by all editor flows.
class CustomerSelectorSheet extends StatelessWidget {
  final List<Customer> customers;
  final void Function(Customer) onSelected;
  final bool showCreateOption;
  final String createOptionSubtitle;
  final Color accentColor;
  final Future<void> Function()? onCreateTap;

  const CustomerSelectorSheet({
    super.key,
    required this.customers,
    required this.onSelected,
    this.showCreateOption = false,
    this.createOptionSubtitle = 'Add a new customer',
    this.accentColor = AppTheme.primaryIndigo,
    this.onCreateTap,
  });

  static Future<void> show(
    BuildContext context, {
    required List<Customer> customers,
    required void Function(Customer) onSelected,
    bool showCreateOption = false,
    String createOptionSubtitle = 'Add a new customer',
    Color accentColor = AppTheme.primaryIndigo,
    Future<void> Function()? onCreateTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => CustomerSelectorSheet(
        customers: customers,
        onSelected: onSelected,
        showCreateOption: showCreateOption,
        createOptionSubtitle: createOptionSubtitle,
        accentColor: accentColor,
        onCreateTap: onCreateTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;

    var allCustomers = List<Customer>.from(customers);
    final searchController = TextEditingController();
    var filtered = allCustomers;

    return StatefulBuilder(
      builder: (context, setModalState) {
        void onSearch(String query) {
          final q = query.toLowerCase();
          setModalState(() {
            filtered = q.isEmpty
                ? allCustomers
                : allCustomers.where((c) {
                    return c.name.toLowerCase().contains(q) ||
                        c.companyName.toLowerCase().contains(q) ||
                        c.phone.contains(q);
                  }).toList();
          });
        }

        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select Customer',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: TextField(
                    controller: searchController,
                    autofocus: true,
                    onChanged: onSearch,
                    decoration: InputDecoration(
                      hintText: 'Search by name, company or phone...',
                      prefixIcon: Icon(Icons.search, color: accentColor),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const Divider(),
                if (showCreateOption) ...[
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.person_add_rounded,
                        color: accentColor,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Create New Customer',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                    subtitle: Text(createOptionSubtitle),
                    onTap: () async {
                      Navigator.pop(context);
                      await onCreateTap?.call();
                    },
                  ),
                  const Divider(height: 1),
                ],
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No customers found',
                            style: TextStyle(
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final customer = filtered[index];
                            return ListTile(
                              title: Text(
                                customer.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(customer.companyName),
                              trailing: customer.outstandingBalance > 0
                                  ? Text(
                                      'Outstanding: ${formatCurrency(customer.outstandingBalance, cs)}',
                                      style: const TextStyle(
                                        color: AppTheme.errorRose,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                              onTap: () {
                                onSelected(customer);
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
