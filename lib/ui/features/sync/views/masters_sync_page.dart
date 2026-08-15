import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/services/error_classification.dart';
import '../../../../data/services/sync_worker.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/sync_item_card.dart';
import '../../route/bloc/route_bloc.dart';
import '../../auth/logout.dart';
import '../../../core/cubit/organization_cubit.dart';
import '../bloc/sync_bloc.dart';
import '../bloc/masters_sync_bloc.dart';
import '../bloc/masters_sync_event.dart';
import '../bloc/masters_sync_state.dart';
import '../widgets/masters_sync_card_list.dart';
import '../widgets/masters_sync_console_panel.dart';
import '../widgets/masters_sync_header.dart';

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
  bool _showConsoleLogs = false;

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
              _showConsoleLogs &&
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
        // Refresh routes / org after a master type finishes (success path).
        BlocListener<MastersSyncBloc, MastersSyncState>(
          listenWhen: (prev, curr) =>
              curr.syncedTypes.length > prev.syncedTypes.length ||
              (prev.bulkInFlight && !curr.bulkInFlight),
          listener: (context, state) {
            context.read<RouteBloc>().add(LoadRoutes());
            if (state.syncedTypes.contains(MasterType.organization)) {
              context.read<OrganizationCubit>().refresh();
            }
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
                    MastersSyncHeader(
                      state: state,
                      isDark: isDark,
                      syncedCount: syncedCount,
                      totalCount: totalCount,
                      onLongPressConsole: () {
                        setState(() => _showConsoleLogs = true);
                      },
                    ),
                    const SizedBox(height: 20),
                    MastersSyncCardList(
                      state: state,
                      isDark: isDark,
                      syncedCount: syncedCount,
                      totalCount: totalCount,
                    ),
                  ],
                ),
              ),
              Visibility(
                visible: _showConsoleLogs,
                child: MastersSyncConsolePanel(
                  state: state,
                  scrollController: _scrollController,
                  onClose: () => setState(() => _showConsoleLogs = false),
                ),
              ),
              _buildBottomBar(context, state.canProceed),
            ],
          );
        },
      ),
    );
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
                onPressed: () => attemptLogout(context),
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
                        // Pushed from Dashboard → pop back. Shown as
                        // SessionGateway body → LoadRoutes rebuilds gateway
                        // into Dashboard once masters are present.
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
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
    // Prefer Zoho `message` (and strip Dio boilerplate) for already-queued
    // verbose errors as well as newly stored friendly ones.
    final displayError =
        rawError == null ? null : humanizeSyncErrorMessage(rawError);

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
            maxLines: 4,
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
      onTap: syncItem.status == SyncStatus.failed && displayError != null
          ? () => _showQueueErrorDialog(
                context,
                title:
                    '${syncItem.type.toUpperCase().replaceAll('_', ' ')} #$shortId',
                message: displayError,
              )
          : null,
    );
  }

  void _showQueueErrorDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
