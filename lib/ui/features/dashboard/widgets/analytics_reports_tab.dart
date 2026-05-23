import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../sync/bloc/sync_bloc.dart';
import 'van_metric_card.dart';

class AnalyticsReportsTab extends StatelessWidget {
  final bool isDark;
  final double todaySales;
  final double todayPayments;
  final double todayExpenses;
  final int completedDeliveries;

  const AnalyticsReportsTab({
    super.key,
    required this.isDark,
    required this.todaySales,
    required this.todayPayments,
    required this.todayExpenses,
    required this.completedDeliveries,
  });

  int _tempMatchLength(String id) {
    return id.length > 8 ? id.length - 8 : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sales & Collection Metrics Cards
              Row(
                children: [
                  Expanded(
                    child: VanMetricCard(
                      title: 'Today Sales (Invoiced)',
                      value: '₹${todaySales.toStringAsFixed(2)}',
                      icon: Icons.point_of_sale_rounded,
                      color: AppTheme.primaryIndigo,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: VanMetricCard(
                      title: 'Collections (Payments)',
                      value: '₹${todayPayments.toStringAsFixed(2)}',
                      icon: Icons.account_balance_wallet_rounded,
                      color: AppTheme.successEmerald,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: VanMetricCard(
                      title: 'Claimed Expenses',
                      value: '₹${todayExpenses.toStringAsFixed(2)}',
                      icon: Icons.receipt_long_rounded,
                      color: AppTheme.errorRose,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: VanMetricCard(
                      title: 'Deliveries Done',
                      value: '$completedDeliveries Clients',
                      icon: Icons.verified_user_rounded,
                      color: AppTheme.infoSky,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Synchronization summary
              Text(
                'Sync Queue Log',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.darkText : AppTheme.lightText,
                ),
              ),
              const SizedBox(height: 12),
              BlocBuilder<SyncBloc, SyncState>(
                builder: (context, syncState) {
                  final list = syncState.queueItems;
                  if (list.isEmpty) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Center(
                          child: Text(
                            'Sync queue is empty. All local work is successfully synchronized with Zoho Books!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return Card(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: list.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1, color: Color(0xFF334155)),
                      itemBuilder: (context, index) {
                        final syncItem = list[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            syncItem.type == 'invoice'
                                ? Icons.description
                                : (syncItem.type == 'receipt' ? Icons.receipt_long : Icons.person_add),
                            color: AppTheme.primaryIndigo,
                          ),
                          title: Text(
                            '${syncItem.type.toUpperCase()} #${syncItem.id.substring(_tempMatchLength(syncItem.id))}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            syncItem.status == SyncStatus.failed
                                ? 'Failed: ${syncItem.errorMessage}'
                                : 'Status: ${syncItem.status.name}',
                            style: TextStyle(
                              color: syncItem.status == SyncStatus.failed
                                  ? AppTheme.errorRose
                                  : (syncItem.status == SyncStatus.syncing
                                      ? AppTheme.infoSky
                                      : AppTheme.warningAmber),
                              fontSize: 11,
                            ),
                          ),
                          trailing: Text(
                            DateFormat('hh:mm a').format(syncItem.timestamp),
                            style: const TextStyle(fontSize: 11),
                          ),
                        );
                      },
                    ),
                  );
                },
              )
            ],
          ),
        ),
      ),
    );
  }
}
