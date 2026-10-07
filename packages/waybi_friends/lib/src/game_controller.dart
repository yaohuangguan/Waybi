import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'journey_engine.dart';
import 'models.dart';
import 'room_life.dart';

class GameController extends ChangeNotifier {
  static final embedded = GameController(saveKey: 'waybi_friends_v1');
  GameController({
    DateTime Function()? clock,
    this.saveKey = 'waybis_way_home_v1',
    JourneyEngine? engine,
  }) : clock = clock ?? DateTime.now,
       engine = engine ?? JourneyEngine();

  final String saveKey;
  String get backupKey => '$saveKey.backup';
  String get pendingRestoreKey => '$saveKey.pending_restore';
  final DateTime Function() clock;
  final JourneyEngine engine;
  SavedGame state = const SavedGame();
  bool ready = false;
  JourneyMemory? latestReturn;
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();
  bool _disposed = false;

  bool get waybiAway => state.activeJourney != null;
  bool isAway(FriendKind kind) => state.activeJourney?.traveller == kind;
  static const bagCapacity = 2;
  RoomLife get roomLife => state.roomLife ?? RoomLife(startedAt: clock());

  Future<void> load() => _loading ??= _load().catchError((Object error) {
    _loading = null;
    throw error;
  });

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(saveKey);
    final backup = prefs.getString(backupKey);
    if (raw != null || backup != null) {
      try {
        state = SavedGame.decode(raw ?? backup!);
      } catch (_) {
        // An unreadable save must never silently become a new, empty journal.
        // Leave the original untouched when no valid backup is available.
        if (backup == null) rethrow;
        state = SavedGame.decode(backup);
        await _save();
      }
    }
    final pending = prefs.getString(pendingRestoreKey);
    if (pending != null) {
      final archive = SavedGame.decode(pending);
      state = state.mergeArchive(archive);
      await _save();
      await prefs.remove(pendingRestoreKey);
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

  Future<void> startJourney({FriendKind traveller = FriendKind.waybi}) async {
    if (!ready || waybiAway) return;
    final now = clock();
    state = state.copyWith(
      activeJourney: engine.start(
        state.selectedItemIds,
        at: now,
        traveller: traveller,
      ),
      roomLife: roomLife.departing(now, traveller),
    );
    _notify();
    await _save();
  }

  Future<void> changeScene(HomeScene scene) async {
    if (!ready) return;
    state = state.copyWith(roomLife: roomLife.changeScene(scene));
    _notify();
    await _save();
  }

  Future<void> interact(FriendKind kind) async {
    if (!ready || isAway(kind)) return;
    state = state.copyWith(
      roomLife: roomLife.interact(kind, clock(), away: waybiAway),
    );
    _notify();
    await _save();
  }

  /// Called only by a confirmed arrival, with no popup over navigation.
  Future<JourneyMemory?> rememberArrival({
    required String tripId,
    required String destinationName,
    String? countryCode,
  }) async {
    await load();
    if (state.memories.any((m) => m.sourceTripId == tripId)) return null;
    final memory = engine.arrival(
      tripId: tripId,
      destinationName: destinationName,
      countryCode: countryCode,
      at: clock(),
    );
    state = state.copyWith(memories: [memory, ...state.memories]);
    latestReturn = memory;
    _notify();
    await _save();
    return memory;
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
      // Keep a complete, independently readable copy before replacing the
      // primary save. Serialized writes preserve the order of concurrent rewards.
      if (!await prefs.setString(backupKey, snapshot)) {
        throw StateError('Could not back up the Friends journal');
      }
      if (!await prefs.setString(saveKey, snapshot)) {
        throw StateError('Could not save the Friends journal');
      }
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
