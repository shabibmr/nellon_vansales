import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/models/customer.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../route/bloc/route_bloc.dart';

class RouteSequenceTab extends StatelessWidget {
  final bool isDark;
  final Function(Customer customer) onCustomerTap;

  const RouteSequenceTab({
    super.key,
    required this.isDark,
    required this.onCustomerTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: BlocBuilder<RouteBloc, RouteState>(
          builder: (context, routeState) {
            if (routeState.isLoading) {
              return const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryIndigo),
              );
            }

            final customers = routeState.filteredCustomers;

            return Column(
              children: [
                // Search Bar header
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextFormField(
                    onChanged: (val) {
                      context.read<RouteBloc>().add(SearchCustomers(val));
                    },
                    decoration: const InputDecoration(
                      hintText: 'Search sequential clients...',
                      prefixIcon: Icon(Icons.search_rounded, color: AppTheme.primaryIndigo),
                    ),
                  ),
                ),

                if (customers.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        'No customers found on this route.',
                        style: TextStyle(
                          color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
                      itemCount: customers.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final customer = customers[index];

                        return Card(
                          child: InkWell(
                            onTap: () => onCustomerTap(customer),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  // Sequence circular badge
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryIndigo.withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        customer.sequence.toString(),
                                        style: const TextStyle(
                                          color: AppTheme.primaryIndigo,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Profile Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          customer.name,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          customer.companyName,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Financial Outstanding Details
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Outstanding',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                        ),
                                      ),
                                      Text(
                                        '₹${customer.outstandingBalance.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                          color: customer.outstandingBalance > 0
                                              ? AppTheme.errorRose
                                              : AppTheme.successEmerald,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.keyboard_arrow_right,
                                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                  )
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
