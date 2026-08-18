import 'dart:async';

import 'package:hardware_button_listener/hardware_button_listener.dart';
import 'package:hardware_button_listener/models/hardware_button.dart';

/// Detects three POWER-key presses landing within [window] and emits on
/// [onTriplePress]. Android-only, backed by `hardware_button_listener`.
class TriplePowerPressDetector {
  TriplePowerPressDetector({this.window = const Duration(milliseconds: 1600)});

  final Duration window;
  final StreamController<void> _controller = StreamController<void>.broadcast();
  final List<DateTime> _presses = [];
  StreamSubscription<HardwareButton>? _sub;

  Stream<void> get onTriplePress => _controller.stream;

  void start() {
    _sub = HardwareButtonListener().listen(_onButton);
  }

  void _onButton(HardwareButton event) {
    if (event.buttonName != 'POWER') return;
    final now = DateTime.now();
    _presses
      ..add(now)
      ..removeWhere((t) => now.difference(t) > window);
    if (_presses.length >= 3) {
      _presses.clear();
      _controller.add(null);
    }
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}
