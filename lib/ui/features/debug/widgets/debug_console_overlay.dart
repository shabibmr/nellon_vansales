import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../data/services/debug_file_logger.dart';
import '../../../../data/services/triple_power_press_detector.dart';

const _minSize = Size(180, 140);
const _defaultSize = Size(320, 240);
const _maxLogLines = 1000;

/// Always-mounted floating debug console. Stacks above the entire app,
/// draggable + pinch-resizable via its header, toggled by a triple
/// power-button press, and streams [DebugFileLogger.logStream] live.
class DebugConsoleOverlay extends StatefulWidget {
  const DebugConsoleOverlay({super.key});

  @override
  State<DebugConsoleOverlay> createState() => _DebugConsoleOverlayState();
}

class _DebugConsoleOverlayState extends State<DebugConsoleOverlay> {
  bool _visible = false;
  Offset? _position;
  Size _size = _defaultSize;
  Size _startSize = _defaultSize;

  final List<String> _logs = [];
  final List<String> _pendingLogs = [];
  Timer? _flushTimer;
  final ScrollController _scrollController = ScrollController();
  late final StreamSubscription<String> _logSub;
  late final TriplePowerPressDetector _powerDetector;
  late final StreamSubscription<void> _triplePressSub;

  @override
  void initState() {
    super.initState();

    DebugFileLogger.readActiveLog().then((content) {
      if (!mounted) return;
      final lines = content.split('\n').where((l) => l.trim().isNotEmpty);
      setState(() => _logs.addAll(lines));
    });

    _logSub = DebugFileLogger.logStream.listen((line) {
      _pendingLogs.add(line);
      _flushTimer ??= Timer(const Duration(milliseconds: 120), _flushPendingLogs);
    });

    _powerDetector = TriplePowerPressDetector()..start();
    _triplePressSub = _powerDetector.onTriplePress.listen((_) {
      setState(() {
        _visible = !_visible;
        if (_visible) _scrollToBottom();
      });
    });
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _logSub.cancel();
    _triplePressSub.cancel();
    _powerDetector.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _flushPendingLogs() {
    _flushTimer = null;
    if (_pendingLogs.isEmpty) return;
    _logs.addAll(_pendingLogs);
    _pendingLogs.clear();
    if (_logs.length > _maxLogLines) {
      _logs.removeRange(0, _logs.length - _maxLogLines);
    }
    if (!mounted) return;
    // Hidden overlay must not rebuild the tree on every log line — that
    // stalls the Android SurfaceView and floods BLASTBufferQueue.
    if (!_visible) return;
    setState(() {});
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _startSize = _size;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Size screenSize) {
    final rawSize = Size(
      _startSize.width * details.scale,
      _startSize.height * details.scale,
    );
    final maxSize = Size(screenSize.width - 32, screenSize.height - 32);
    final clampedSize = Size(
      rawSize.width.clamp(_minSize.width, maxSize.width).toDouble(),
      rawSize.height.clamp(_minSize.height, maxSize.height).toDouble(),
    );

    final current = _position ?? _defaultPosition(screenSize);
    final rawPosition = current + details.focalPointDelta;
    final clampedPosition = Offset(
      rawPosition.dx.clamp(0.0, screenSize.width - clampedSize.width).toDouble(),
      rawPosition.dy.clamp(0.0, screenSize.height - clampedSize.height).toDouble(),
    );

    setState(() {
      _size = clampedSize;
      _position = clampedPosition;
    });
  }

  Offset _defaultPosition(Size screenSize) {
    return Offset(16, screenSize.height - _size.height - 96);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final position = _position ?? _defaultPosition(screenSize);

    return IgnorePointer(
      ignoring: !_visible,
      child: Stack(
        children: [
          if (_visible)
            Positioned(
              left: position.dx,
              top: position.dy,
              width: _size.width,
              height: _size.height,
              child: _ConsolePanel(
                logs: _logs,
                scrollController: _scrollController,
                onScaleStart: _onScaleStart,
                onScaleUpdate: (details) => _onScaleUpdate(details, screenSize),
                onClear: () {
                  DebugFileLogger.clearActiveLog();
                  setState(() => _logs.clear());
                },
                onClose: () => setState(() => _visible = false),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConsolePanel extends StatelessWidget {
  const _ConsolePanel({
    required this.logs,
    required this.scrollController,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onClear,
    required this.onClose,
  });

  final List<String> logs;
  final ScrollController scrollController;
  final GestureScaleStartCallback onScaleStart;
  final GestureScaleUpdateCallback onScaleUpdate;
  final VoidCallback onClear;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade800),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onScaleStart: onScaleStart,
              onScaleUpdate: onScaleUpdate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: Colors.grey.shade900,
                child: Row(
                  children: [
                    const Icon(Icons.terminal_rounded, color: Colors.greenAccent, size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'DEBUG CONSOLE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: onClear,
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
                      child: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: logs.isEmpty
                  ? const Center(
                      child: Text(
                        'No logs yet.',
                        style: TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'monospace'),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(8),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final line = logs[index];
                        final lower = line.toLowerCase();
                        Color color = Colors.white70;
                        if (lower.contains('error') || lower.contains('failed')) {
                          color = Colors.redAccent;
                        } else if (lower.contains('success') || lower.contains('synced')) {
                          color = Colors.greenAccent;
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            line,
                            style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace'),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
