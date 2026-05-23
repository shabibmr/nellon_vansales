import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/services/sync_worker.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../route/bloc/route_bloc.dart';

class MastersSyncPage extends StatefulWidget {
  const MastersSyncPage({super.key});

  @override
  State<MastersSyncPage> createState() => _MastersSyncPageState();
}

class _MastersSyncPageState extends State<MastersSyncPage> {
  final Set<MasterType> _inFlight = {};
  bool _bulkInFlight = false;
  final Map<MasterType, String?> _lastError = {};

  Future<void> _syncOne(MasterType type) async {
    if (_inFlight.contains(type) || _bulkInFlight) return;
    setState(() {
      _inFlight.add(type);
      _lastError[type] = null;
    });
    try {
      await context.read<SyncRepository>().syncMaster(type);
    } catch (e) {
      setState(() => _lastError[type] = e.toString());
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
    });
    try {
      await context.read<SyncRepository>().refreshMasterData();
    } finally {
      if (mounted) setState(() => _bulkInFlight = false);
      if (mounted) context.read<RouteBloc>().add(LoadRoutes());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Master Data'),
        backgroundColor: AppTheme.primaryIndigo,
        foregroundColor: Colors.white,
      ),
      body: Column(
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
                      : IconButton(
                          icon: const Icon(Icons.sync, color: AppTheme.primaryIndigo),
                          onPressed: () => _syncOne(type),
                        ),
                  onTap: isBusy ? null : () => _syncOne(type),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
