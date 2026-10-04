import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'journey_engine.dart';
import 'models.dart';
import 'room_life.dart';

class GameController extends ChangeNotifier {
  GameController({
    DateTime Function()? clock,
    this.saveKey = 'waybis_way_home_v1',
    JourneyEngine? engine,
  }) : clock = clock ?? DateTime.now,
       engine = engine ?? JourneyEngine();

  final String saveKey;
  final DateTime Function() clock;
  final JourneyEngine engine;
  SavedGame state = const SavedGame();
  bool ready = false;
  JourneyMemory? latestReturn;
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();
  bool _disposed = false;

  bool get waybiAway => state.activeJourney != null;
  static const bagCapacity = 2;
  RoomLife get roomLife => state.roomLife ?? RoomLife(startedAt: clock());

  Future<void> load() => _loading ??= _load().catchError((Object error) {
    _loading = null;
    throw error;
  });

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(saveKey);
    if (raw != null) {
      try {
        state = SavedGame.decode(raw);
      } catch (_) {
        state = const SavedGame();
      }
    }
    if (state.roomLife == null) {
      state = state.copyWith(roomLife: RoomLife(startedAt: clock()));
      await _save();
    }
    ready = true;
    await tick();
    _notify();
  }

  Future<bool> toggleItem(String id) async {
    if (!ready || waybiAway || !travelItems.any((item) => item.id == id)) {
      return false;
    }
    final selected = [...state.selectedItemIds];
    if (selected.contains(id)) {
      selected.remove(id);
    } else {
      if (selected.length >= bagCapacity) return false;
      selected.add(id);
    }
    state = state.copyWith(selectedItemIds: selected);
    await _save();
    _notify();
    return true;
  }

  Future<void> startJourney() async {
    if (!ready || waybiAway) return;
    final now = clock();
    state = state.copyWith(
      activeJourney: engine.start(state.selectedItemIds, at: now),
      roomLife: roomLife.departing(now),
    );
    _notify();
    await _save();
  }

  Future<void> tick() async {
    final active = state.activeJourney;
    if (!ready || active == null || clock().isBefore(active.returnAt)) return;
    await _complete(active, active.returnAt);
  }

  Future<void> bringWaybiHomeForPrototype() async {
    final active = state.activeJourney;
    if (active != null) await _complete(active, clock());
  }

  Future<void> _complete(ActiveJourney active, DateTime at) async {
    if (!identical(state.activeJourney, active)) return;
    final memory = engine.finish(active, at: at);
    // Clear before awaiting storage so concurrent ticks cannot add twice.
    state = state.copyWith(
      clearActiveJourney: true,
      roomLife: roomLife.arriving(at),
      memories: [memory, ...state.memories],
    );
    latestReturn = memory;
    _notify();
    await _save();
  }

  JourneyMemory? takeLatestReturn() {
    final value = latestReturn;
    latestReturn = null;
    return value;
  }

  Future<void> reset() async {
    state = SavedGame(roomLife: RoomLife(startedAt: clock()));
    latestReturn = null;
    await _save();
    _notify();
  }

  Future<void> _save() {
    final snapshot = state.encode();
    final write = _writes.catchError((Object _) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(saveKey, snapshot);
    });
    _writes = write;
    return write;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
