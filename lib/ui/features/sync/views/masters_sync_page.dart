import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/services/sync_worker.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../core/theme/app_theme.dart';
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

class _MastersSyncPageState extends State<MastersSyncPage> with SingleTickerProviderStateMixin {
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
    _statusSubscription = context.read<SyncRepository>().syncStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _consoleLogs.add('[${DateTime.now().toLocal().toString().substring(11, 19)}] $status');
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
        setState(() => _lastError[type] = e.toString().replaceAll('Exception: ', ''));
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
          _bulkSyncStatus = 'Sync completed but some core databases are empty. Try syncing again.';
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
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.cloud_sync, size: 18), text: 'Sync Masters'),
            Tab(icon: Icon(Icons.list_alt, size: 18), text: 'Sync Queue'),
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

  Widget _buildSyncMastersTab(bool isDark, bool hasMasters) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _bulkInFlight ? null : _syncAll,
              icon: _bulkInFlight
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_sync),
              label: Text(_bulkInFlight ? 'Syncing all…' : 'Sync All Masters'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: AppTheme.primaryIndigo,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ),
        if (_bulkSyncStatus != null) ...[
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _bulkSyncSuccess == true
                  ? (isDark ? Colors.green.withAlpha(40) : const Color(0xFFE8F5E9))
                  : _bulkSyncSuccess == false
                      ? (isDark ? AppTheme.errorRose.withAlpha(40) : const Color(0xFFFFEBEE))
                      : (isDark ? AppTheme.primaryIndigo.withAlpha(40) : const Color(0xFFE8EAF6)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _bulkSyncSuccess == true
                    ? Colors.green.withAlpha(100)
                    : _bulkSyncSuccess == false
                        ? AppTheme.errorRose.withAlpha(100)
                        : AppTheme.primaryIndigo.withAlpha(100),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _bulkSyncSuccess == true
                      ? Icons.check_circle_rounded
                      : _bulkSyncSuccess == false
                          ? Icons.error_outline_rounded
                          : Icons.sync_outlined,
                  color: _bulkSyncSuccess == true
                      ? Colors.green
                      : _bulkSyncSuccess == false
                          ? AppTheme.errorRose
                          : AppTheme.primaryIndigo,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _bulkSyncStatus!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _bulkSyncSuccess == true
                          ? (isDark ? Colors.green[200] : const Color(0xFF2E7D32))
                          : _bulkSyncSuccess == false
                              ? (isDark ? Colors.red[200] : const Color(0xFFC62828))
                              : (isDark ? Colors.indigo[200] : AppTheme.primaryIndigo),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: MasterType.values.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final type = MasterType.values[index];
              final isBusy = _inFlight.contains(type) || _bulkInFlight;
              final error = _lastError[type];
              return ListTile(
                leading: const Icon(Icons.dataset, color: AppTheme.primaryIndigo),
                title: Text(type.label),
                subtitle: error != null
                    ? Text(error, style: const TextStyle(color: Colors.red, fontSize: 12))
                    : null,
                trailing: isBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _syncedTypes.contains(type) && error == null
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : IconButton(
                            icon: const Icon(Icons.sync, color: AppTheme.primaryIndigo),
                            onPressed: () => _syncOne(type),
                          ),
                onTap: isBusy ? null : () => _syncOne(type),
              );
            },
          ),
        ),
        _buildConsoleLogs(),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(12),
                blurRadius: 10,
                offset: const Offset(0, -5),
              )
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
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

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
                  Icon(Icons.check_circle_outline_rounded,
                      size: 56,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                  const SizedBox(height: 16),
                  Text(
                    'Sync queue is empty.\nAll local work is synchronized with Zoho Books!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final syncItem = list[index];
            final shortId = syncItem.id.length > 8
                ? syncItem.id.substring(syncItem.id.length - 8)
                : syncItem.id;
            return ListTile(
              dense: true,
              leading: Icon(
                syncItem.type == 'invoice'
                    ? Icons.description
                    : (syncItem.type == 'receipt'
                        ? Icons.receipt_long
                        : (syncItem.type == 'expense'
                            ? Icons.local_gas_station
                            : Icons.person_add)),
                color: AppTheme.primaryIndigo,
              ),
              title: Text(
                '${syncItem.type.toUpperCase()} #$shortId',
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
        );
      },
    );
  }

  Widget _buildConsoleLogs() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.black : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
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
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.terminal, color: Colors.greenAccent, size: 16),
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
                      if (log.toLowerCase().contains('failed') || log.toLowerCase().contains('error')) {
                        textColor = Colors.redAccent;
                      } else if (log.toLowerCase().contains('synced') || log.toLowerCase().contains('success')) {
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
