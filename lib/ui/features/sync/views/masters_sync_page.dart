import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/services/sync_worker.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/sync_item_card.dart';
import '../../route/bloc/route_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../bloc/sync_bloc.dart';

/// The Core Master Data Bootstrap / Sync Screen.
///
/// Two tabs: "Sync Masters" for downloading org/items/taxes data from Zoho,
/// and "Sync Queue" to inspect offline transaction upload status.
class MastersSyncPage extends StatefulWidget {
  /// Creates a new [MastersSyncPage].
  const MastersSyncPage({super.key});

  @override
  State<MastersSyncPage> createState() => _MastersSyncPageState();
}

class _MastersSyncPageState extends State<MastersSyncPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final Set<MasterType> _inFlight = {};
  bool _bulkInFlight = false;
  final Map<MasterType, String?> _lastError = {};
  final Set<MasterType> _syncedTypes = {};
  String? _bulkSyncStatus;
  bool? _bulkSyncSuccess;

  StreamSubscription<String>? _statusSubscription;
  final List<String> _consoleLogs = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _statusSubscription = context.read<SyncRepository>().syncStatusStream.listen((
      status,
    ) {
      if (mounted) {
        setState(() {
          _consoleLogs.add(
            '[${DateTime.now().toLocal().toString().substring(11, 19)}] $status',
          );
          if (_consoleLogs.length > 100) {
            _consoleLogs.removeAt(0);
          }
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _statusSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _syncOne(MasterType type) async {
    if (_inFlight.contains(type) || _bulkInFlight) return;
    setState(() {
      _inFlight.add(type);
      _lastError[type] = null;
      _syncedTypes.remove(type);
    });
    try {
      await context.read<SyncRepository>().syncMaster(type);
      if (mounted) {
        setState(() => _syncedTypes.add(type));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _lastError[type] = e.toString().replaceAll('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _inFlight.remove(type));
      if (mounted) context.read<RouteBloc>().add(LoadRoutes());
    }
  }

  Future<void> _syncAll() async {
    if (_bulkInFlight) return;
    setState(() {
      _bulkInFlight = true;
      _lastError.clear();
      _syncedTypes.clear();
      _bulkSyncStatus = 'Sync in progress...';
      _bulkSyncSuccess = null;
    });
    final syncRepo = context.read<SyncRepository>();
    try {
      for (final type in MasterType.values) {
        if (!mounted) break;
        setState(() {
          _inFlight.add(type);
          _lastError[type] = null;
        });
        try {
          await syncRepo.syncMaster(type);
          if (mounted) {
            setState(() {
              _syncedTypes.add(type);
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _lastError[type] = e.toString().replaceAll('Exception: ', '');
            });
          }
        } finally {
          if (mounted) {
            setState(() {
              _inFlight.remove(type);
            });
          }
        }
      }

      final hasMasters = syncRepo.hasCoreMasters();
      setState(() {
        if (hasMasters) {
          _bulkSyncStatus = 'Master data sync completed successfully!';
          _bulkSyncSuccess = true;
        } else {
          _bulkSyncStatus =
              'Sync completed but some core databases are empty. Try syncing again.';
          _bulkSyncSuccess = false;
        }
      });
    } catch (e) {
      setState(() {
        _bulkSyncStatus = 'Sync failed: $e';
        _bulkSyncSuccess = false;
      });
    } finally {
      if (mounted) setState(() => _bulkInFlight = false);
      if (mounted) context.read<RouteBloc>().add(LoadRoutes());
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMasters = context.read<SyncRepository>().hasCoreMasters();
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
              text: 'Sync Queue',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSyncMastersTab(isDark, hasMasters),
          _buildSyncQueueTab(isDark),
        ],
      ),
    );
  }

  // --- Sync Masters Tab ---

  Widget _buildSyncMastersTab(bool isDark, bool hasMasters) {
    final syncedCount = _syncedTypes.length;
    final totalCount = MasterType.values.length;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            children: [
              _buildHeroCard(isDark, syncedCount, totalCount),
              if (_bulkSyncStatus != null) ...[
                const SizedBox(height: 16),
                _buildStatusBanner(isDark),
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
                  child: _buildMasterCard(type, isDark),
                ),
              ),
            ],
          ),
        ),
        _buildConsoleLogs(),
        _buildBottomBar(hasMasters),
      ],
    );
  }

  Widget _buildHeroCard(bool isDark, int syncedCount, int totalCount) {
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
            color: AppTheme.primaryIndigo.withAlpha(70),
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
                  color: Colors.white.withAlpha(40),
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
                      'Download the latest catalog from Zoho Books',
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
              value: _bulkInFlight && progress == 0 ? null : progress,
              minHeight: 8,
              backgroundColor: Colors.white.withAlpha(50),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _bulkInFlight ? null : _syncAll,
              icon: _bulkInFlight
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryIndigo,
                      ),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(_bulkInFlight ? 'Syncing all…' : 'Sync All Masters'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.primaryIndigo,
                disabledBackgroundColor: Colors.white.withAlpha(180),
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

  Widget _buildStatusBanner(bool isDark) {
    final success = _bulkSyncSuccess;
    final Color bg = success == true
        ? (isDark
              ? AppTheme.successEmerald.withAlpha(40)
              : const Color(0xFFE8F5E9))
        : success == false
        ? (isDark ? AppTheme.errorRose.withAlpha(40) : const Color(0xFFFFEBEE))
        : (isDark
              ? AppTheme.primaryIndigo.withAlpha(40)
              : const Color(0xFFE8EAF6));
    final Color border = success == true
        ? AppTheme.successEmerald.withAlpha(100)
        : success == false
        ? AppTheme.errorRose.withAlpha(100)
        : AppTheme.primaryIndigo.withAlpha(100);
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
              _bulkSyncStatus!,
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

  Widget _buildMasterCard(MasterType type, bool isDark) {
    final isBusy = _inFlight.contains(type) || _bulkInFlight;
    final error = _lastError[type];
    final isSynced = _syncedTypes.contains(type) && error == null;

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
      onTap: isBusy ? null : () => _syncOne(type),
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
      case MasterType.openInvoices:
        return Icons.description_rounded;
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
      case MasterType.openInvoices:
        return 'Outstanding invoices for collection';
    }
  }

  Widget _buildBottomBar(bool hasMasters) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
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
                onPressed: () {
                  context.read<AuthBloc>().add(LogoutRequested());
                },
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
                      color: AppTheme.successEmerald.withAlpha(30),
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

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (context, index) {
            final syncItem = list[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildQueueCard(syncItem, isDark),
            );
          },
        );
      },
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
        if (syncItem.status == SyncStatus.failed &&
            syncItem.errorMessage != null) ...[
          const SizedBox(height: 6),
          Text(
            syncItem.errorMessage!,
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

  Widget _buildConsoleLogs() {
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
                if (_consoleLogs.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _consoleLogs.clear();
                      });
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
            child: _consoleLogs.isEmpty
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
                    itemCount: _consoleLogs.length,
                    itemBuilder: (context, index) {
                      final log = _consoleLogs[index];
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
