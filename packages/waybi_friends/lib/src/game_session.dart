import 'dart:async';

import 'package:flutter/widgets.dart';

import 'game_controller.dart';

/// Owned by the open room, so navigation screens never run game timers or popups.
class GameSession extends ChangeNotifier with WidgetsBindingObserver {
  GameSession({
    GameController? controller,
    String saveKey = 'waybis_way_home_v1',
  }) : controller = controller ?? GameController(saveKey: saveKey);
  final GameController controller;
  Timer? _timer;
  bool foreground = true;
  bool _disposed = false;
  Object? error;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    controller.addListener(_changed);
    unawaited(load());
    _schedule();
  }

  Future<void> load() async {
    error = null;
    try {
      await controller.load();
    } catch (e) {
      error = e;
    }
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _schedule() {
    _timer?.cancel();
    if (foreground) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  Future<void> _tick() async {
    try {
      await controller.tick();
      _changed();
    } catch (e) {
      error = e;
      _changed();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    _schedule();
    if (foreground) unawaited(_tick());
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_changed);
    controller.dispose();
    super.dispose();
  }
}
