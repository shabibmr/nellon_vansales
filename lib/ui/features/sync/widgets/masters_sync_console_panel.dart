import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/masters_sync_bloc.dart';
import '../bloc/masters_sync_event.dart';
import '../bloc/masters_sync_state.dart';

class MastersSyncConsolePanel extends StatelessWidget {
  final MastersSyncState state;
  final ScrollController scrollController;
  final VoidCallback onClose;

  const MastersSyncConsolePanel({
    super.key,
    required this.state,
    required this.scrollController,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
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
              children: [
                const Icon(
                  Icons.terminal_rounded,
                  color: Colors.greenAccent,
                  size: 16,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'DIAGNOSTIC LOGS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                if (state.consoleLogs.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      context.read<MastersSyncBloc>().add(ClearLogsRequested());
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'CLEAR',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: onClose,
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white70,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SelectionArea(
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
                      controller: scrollController,
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
          ),
        ],
      ),
    );
  }
}
