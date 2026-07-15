import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/sync_worker.dart';
import '../../../../data/services/injection.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/sync_item_card.dart';
import '../../route/bloc/route_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../bloc/sync_bloc.dart';
import '../bloc/masters_sync_bloc.dart';
import '../bloc/masters_sync_event.dart';
import '../bloc/masters_sync_state.dart';

/// The Core Master Data Bootstrap / Sync Screen.
///
/// Two tabs: "Sync Masters" for downloading reference data from Zoho
/// (organization, items, customers, taxes, etc.), and "Sync Queue" to
/// **inspect** offline upload status only.
///
/// This page never pulls or pushes business transactions (invoices, receipts,
/// orders, returns, expenses). Those upload automatically via [SyncWorker]
/// when connectivity is available.
class MastersSyncPage extends StatelessWidget {
  /// Creates a new [MastersSyncPage].
  const MastersSyncPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<MastersSyncBloc>(
      create: (_) => MastersSyncBloc(
        syncRepository: context.read<SyncRepository>(),
      )..add(MastersSyncStarted()),
      child: const _MastersSyncPageView(),
    );
  }
}

class _MastersSyncPageView extends StatefulWidget {
  const _MastersSyncPageView();

  @override
  State<_MastersSyncPageView> createState() => _MastersSyncPageViewState();
}

class _MastersSyncPageViewState extends State<_MastersSyncPageView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Blocks logout if today's route activity hasn't been reconciled yet via
  /// the Cash Closing workflow — otherwise a day's cash-in-hand discrepancy
  /// could be walked away from unnoticed.
  Future<void> _attemptLogout(BuildContext context) async {
    final hasPendingClosing = sl<HiveDatabaseService>()
        .hasPendingCashClosingForToday();
    if (!hasPendingClosing) {
      context.read<AuthBloc>().add(LogoutRequested());
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cash Closing Required'),
        content: const Text(
          "You have unreconciled sales activity today. Please complete "
          "today's Cash Closing from the Dashboard before logging out.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Master Data'),
        backgroundColor: AppTheme.primaryIndigo,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(
              icon: Icon(Icons.cloud_sync_rounded, size: 18),
              text: 'Sync Masters',
            ),
            Tab(
              icon: Icon(Icons.list_alt_rounded, size: 18),
              text: 'Upload Queue',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSyncMastersTab(isDark),
          _buildSyncQueueTab(isDark),
        ],
      ),
    );
  }

  Widget _buildSyncMastersTab(bool isDark) {
    return MultiBlocListener(
      listeners: [
        BlocListener<MastersSyncBloc, MastersSyncState>(
          listenWhen: (prev, curr) =>
              prev.consoleLogs.length < curr.consoleLogs.length,
          listener: (context, state) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
            });
          },
        ),
        // Refresh routes after a master type finishes (success path).
        BlocListener<MastersSyncBloc, MastersSyncState>(
          listenWhen: (prev, curr) =>
              curr.syncedTypes.length > prev.syncedTypes.length ||
              (prev.bulkInFlight && !curr.bulkInFlight),
          listener: (context, state) {
            context.read<RouteBloc>().add(LoadRoutes());
          },
        ),
      ],
      child: BlocBuilder<MastersSyncBloc, MastersSyncState>(
        builder: (context, state) {
          final syncedCount = state.syncedTypes.length;
          final totalCount = MasterType.values.length;

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  children: [
                    _buildHeroCard(context, state, isDark, syncedCount, totalCount),
                    if (state.bulkSyncStatus != null) ...[
                      const SizedBox(height: 16),
                      _buildStatusBanner(state, isDark),
                    ],
                    const SizedBox(height: 20),
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
                ),
              ),
              _buildConsoleLogs(context, state),
              _buildBottomBar(context, state.canProceed),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeroCard(
    BuildContext context,
    MastersSyncState state,
    bool isDark,
    int syncedCount,
    int totalCount,
  ) {
    final progress = totalCount == 0 ? 0.0 : syncedCount / totalCount;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryIndigo, AppTheme.primaryDarkIndigo],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryIndigo.withValues(alpha: 0.27),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.cloud_sync_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Master Data',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Reference data only — no invoices or other transactions',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                '$syncedCount of $totalCount synced',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: state.bulkInFlight && progress == 0 ? null : progress,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: state.bulkInFlight
                  ? null
                  : () => context.read<MastersSyncBloc>().add(SyncAllRequested()),
              icon: state.bulkInFlight
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryIndigo,
                      ),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(state.bulkInFlight ? 'Syncing all…' : 'Sync All Masters'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.primaryIndigo,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.7),
                disabledForegroundColor: AppTheme.primaryIndigo,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(MastersSyncState state, bool isDark) {
    final success = state.bulkSyncSuccess;
    final Color bg = success == true
        ? (isDark
              ? AppTheme.successEmerald.withValues(alpha: 0.16)
              : const Color(0xFFE8F5E9))
        : success == false
        ? (isDark ? AppTheme.errorRose.withValues(alpha: 0.16) : const Color(0xFFFFEBEE))
        : (isDark
              ? AppTheme.primaryIndigo.withValues(alpha: 0.16)
              : const Color(0xFFE8EAF6));
    final Color border = success == true
        ? AppTheme.successEmerald.withValues(alpha: 0.39)
        : success == false
        ? AppTheme.errorRose.withValues(alpha: 0.39)
        : AppTheme.primaryIndigo.withValues(alpha: 0.39);
    final Color fg = success == true
        ? (isDark ? Colors.green[200]! : const Color(0xFF2E7D32))
        : success == false
        ? (isDark ? Colors.red[200]! : const Color(0xFFC62828))
        : (isDark ? Colors.indigo[200]! : AppTheme.primaryIndigo);
    final IconData icon = success == true
        ? Icons.check_circle_rounded
        : success == false
        ? Icons.error_outline_rounded
        : Icons.sync_outlined;
    final Color iconColor = success == true
        ? AppTheme.successEmerald
        : success == false
        ? AppTheme.errorRose
        : AppTheme.primaryIndigo;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              state.bulkSyncStatus!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
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

  Widget _buildBottomBar(BuildContext context, bool hasMasters) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: () => _attemptLogout(context),
                icon: const Icon(Icons.logout),
                label: const Text('LOG OUT'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  foregroundColor: AppTheme.errorRose,
                  side: const BorderSide(color: AppTheme.errorRose),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: ElevatedButton.icon(
                onPressed: hasMasters
                    ? () {
                        context.read<RouteBloc>().add(LoadRoutes());
                      }
                    : null,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('PROCEED'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: AppTheme.primaryIndigo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Sync Queue Tab ---

  Widget _buildSyncQueueTab(bool isDark) {
    return BlocBuilder<SyncBloc, SyncState>(
      builder: (context, syncState) {
        final list = syncState.queueItems;
        final failedCount = list
            .where((i) => i.status == SyncStatus.failed)
            .length;

        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.successEmerald.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 48,
                      color: AppTheme.successEmerald,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'All caught up!',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppTheme.darkText : AppTheme.lightText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'All local work is synchronized with Zoho Books.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: [
            if (failedCount > 0) _buildQueueActionsBar(context, failedCount, syncState),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final syncItem = list[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildQueueCard(syncItem, isDark),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQueueActionsBar(BuildContext context, int failedCount, SyncState syncState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppTheme.errorRose.withValues(alpha: 0.08),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$failedCount item${failedCount == 1 ? '' : 's'} failed — '
              'uploads retry automatically when online',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.errorRose,
              ),
            ),
          ),
          // Queue is view/manage only on this page — never push transactions here.
          TextButton.icon(
            onPressed: () =>
                context.read<SyncBloc>().add(ClearFailedItemsRequested()),
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: const Text('Clear Failed'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorRose),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueCard(SyncQueueItem syncItem, bool isDark) {
    final shortId = syncItem.id.length > 8
        ? syncItem.id.substring(syncItem.id.length - 8)
        : syncItem.id;

    final Color statusColor = syncItem.status == SyncStatus.failed
        ? AppTheme.errorRose
        : (syncItem.status == SyncStatus.syncing
              ? AppTheme.infoSky
              : AppTheme.warningAmber);

    final IconData statusIcon = syncItem.status == SyncStatus.failed
        ? Icons.error_outline_rounded
        : (syncItem.status == SyncStatus.syncing
              ? Icons.sync_rounded
              : Icons.schedule_rounded);

    final String statusLabel = syncItem.status == SyncStatus.failed
        ? 'Failed'
        : (syncItem.status.name[0].toUpperCase() +
              syncItem.status.name.substring(1));

    final IconData typeIcon = syncItem.type == 'invoice'
        ? Icons.description_rounded
        : (syncItem.type == 'receipt'
              ? Icons.receipt_long_rounded
              : (syncItem.type == 'expense'
                    ? Icons.local_gas_station_rounded
                    : (syncItem.type == 'sales_order'
                          ? Icons.assignment_rounded
                          : (syncItem.type == 'return'
                                ? Icons.assignment_return_rounded
                                : Icons.person_add_rounded))));

    final rawError = syncItem.errorMessage;
    final isRetryable = rawError?.startsWith('[Retryable]') ?? false;
    final isNeedsAttention = rawError?.startsWith('[Needs Attention]') ?? false;
    final displayError = rawError
        ?.replaceFirst('[Retryable] ', '')
        .replaceFirst('[Needs Attention] ', '');

    final subtitleWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            StatusPill(
              label: statusLabel,
              color: statusColor,
              icon: statusIcon,
            ),
            const SizedBox(width: 8),
            Text(
              DateFormat('hh:mm a').format(syncItem.timestamp),
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
              ),
            ),
          ],
        ),
        if (syncItem.status == SyncStatus.failed && displayError != null) ...[
          const SizedBox(height: 6),
          if (isRetryable)
            const StatusPill(
              label: 'Retryable',
              color: AppTheme.infoSky,
              icon: Icons.wifi_off_rounded,
            )
          else if (isNeedsAttention)
            const StatusPill(
              label: 'Needs Attention',
              color: AppTheme.errorRose,
              icon: Icons.report_problem_outlined,
            ),
          const SizedBox(height: 4),
          Text(
            displayError,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppTheme.errorRose),
          ),
        ],
      ],
    );

    return SyncItemCard(
      icon: typeIcon,
      title: '${syncItem.type.toUpperCase().replaceAll('_', ' ')} #$shortId',
      subtitle: '',
      subtitleWidget: subtitleWidget,
      accentColor: AppTheme.primaryIndigo,
      trailing: const SizedBox.shrink(),
      hasError: syncItem.status == SyncStatus.failed,
    );
  }

  // --- Diagnostic Console ---

  Widget _buildConsoleLogs(BuildContext context, MastersSyncState state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.black : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.terminal_rounded,
                      color: Colors.greenAccent,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'DIAGNOSTIC LOGS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                if (state.consoleLogs.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      context.read<MastersSyncBloc>().add(ClearLogsRequested());
                    },
                    child: const Text(
                      'CLEAR',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: state.consoleLogs.isEmpty
                ? const Center(
                    child: Text(
                      'No logs yet. Start sync to capture diagnostics.',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: state.consoleLogs.length,
                    itemBuilder: (context, index) {
                      final log = state.consoleLogs[index];
                      Color textColor = Colors.white70;
                      if (log.toLowerCase().contains('failed') ||
                          log.toLowerCase().contains('error')) {
                        textColor = Colors.redAccent;
                      } else if (log.toLowerCase().contains('synced') ||
                          log.toLowerCase().contains('success')) {
                        textColor = Colors.greenAccent;
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          log,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
