import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/sync_item_card.dart';
import '../../../../data/services/sync_worker.dart';
import '../bloc/masters_sync_bloc.dart';
import '../bloc/masters_sync_event.dart';
import '../bloc/masters_sync_state.dart';

class MastersSyncCardList extends StatelessWidget {
  final MastersSyncState state;
  final bool isDark;
  final int syncedCount;
  final int totalCount;

  const MastersSyncCardList({
    super.key,
    required this.state,
    required this.isDark,
    required this.syncedCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Row(
            children: [
              Text(
                'DATA CATEGORIES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '$syncedCount / $totalCount',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
        ...MasterType.values.map(
          (type) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildMasterCard(context, state, type, isDark),
          ),
        ),
      ],
    );
  }

  Widget _buildMasterCard(
    BuildContext context,
    MastersSyncState state,
    MasterType type,
    bool isDark,
  ) {
    final isBusy = state.inFlight.contains(type) || state.bulkInFlight;
    final error = state.lastError[type];
    final isSynced = state.syncedTypes.contains(type) && error == null;

    Color accent;
    Widget trailing;
    if (isBusy) {
      accent = AppTheme.infoSky;
      trailing = const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: AppTheme.infoSky,
        ),
      );
    } else if (isSynced) {
      accent = AppTheme.successEmerald;
      trailing = const StatusPill(
        label: 'Synced',
        color: AppTheme.successEmerald,
        icon: Icons.check_circle_rounded,
      );
    } else if (error != null) {
      accent = AppTheme.errorRose;
      trailing = const StatusPill(
        label: 'Retry',
        color: AppTheme.errorRose,
        icon: Icons.refresh_rounded,
      );
    } else {
      accent = AppTheme.primaryIndigo;
      trailing = const StatusPill(
        label: 'Sync',
        color: AppTheme.primaryIndigo,
        icon: Icons.sync_rounded,
      );
    }

    return SyncItemCard(
      icon: _iconForType(type),
      title: type.label,
      subtitle: error ?? _descForType(type),
      accentColor: accent,
      trailing: trailing,
      onTap: isBusy
          ? null
          : () {
              context.read<MastersSyncBloc>().add(SyncOneRequested(type));
            },
      hasError: error != null,
    );
  }

  IconData _iconForType(MasterType type) {
    switch (type) {
      case MasterType.organization:
        return Icons.business_rounded;
      case MasterType.warehouses:
        return Icons.warehouse_rounded;
      case MasterType.paymentAccounts:
        return Icons.account_balance_wallet_rounded;
      case MasterType.taxes:
        return Icons.percent_rounded;
      case MasterType.expenseAccounts:
        return Icons.request_quote_rounded;
      case MasterType.routes:
        return Icons.route_rounded;
      case MasterType.items:
        return Icons.inventory_2_rounded;
      case MasterType.customers:
        return Icons.people_alt_rounded;
      case MasterType.salespersons:
        return Icons.badge_rounded;
    }
  }

  String _descForType(MasterType type) {
    switch (type) {
      case MasterType.organization:
        return 'Currency, formatting & org settings';
      case MasterType.warehouses:
        return 'Van compartments & stock locations';
      case MasterType.paymentAccounts:
        return 'Bank & cash accounts for receipts';
      case MasterType.taxes:
        return 'VAT rates & tax configurations';
      case MasterType.expenseAccounts:
        return 'Categories for on-route expenses';
      case MasterType.routes:
        return 'Delivery routes & sequences';
      case MasterType.items:
        return 'Product catalog & van stock';
      case MasterType.customers:
        return 'Contacts, balances & credit limits';
      case MasterType.salespersons:
        return 'Sales users & location assignments';
    }
  }
}
