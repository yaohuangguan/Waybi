import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_friends/waybi_friends.dart';

import 'account_repository.dart';

enum FriendsBackupStatus { deviceOnly, syncing, backedUp, offline }

/// Account-scoped local saves remain usable when the network is unavailable.
/// Every async boundary checks the account, so a late response cannot restore
/// one person's journal into another person's session.
class FriendsBackupService extends ChangeNotifier {
  FriendsBackupService(this.account, {GameController? controller})
    : controller = controller ?? GameController.embedded;

  final AccountRepository account;
  final GameController controller;
  FriendsBackupStatus status = FriendsBackupStatus.deviceOnly;
  DateTime? lastBackupAt;
  Timer? _debounce;
  Timer? _retry;
  String? _requestedAccount;
  int _generation = 0;
  bool _started = false;
  bool _disposed = false;
  bool _applying = false;
  bool _busy = false;
  Future<void> _bindings = Future<void>.value();

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    account.addListener(_accountChanged);
    controller.addListener(_gameChanged);
    // A saved session can temporarily have no profile while offline. Keep
    // that account's local journal accessible until authentication resolves.
    _requestedAccount = account.signedIn
        ? (account.profile?.id ?? prefs.getString('waybi_friends.last_account'))
        : null;
    await _bind(_requestedAccount, ++_generation);
    _retry = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(sync()),
    );
  }

  void _accountChanged() {
    final next = account.profile?.id;
    if (account.signedIn && (next == null || next.isEmpty)) return;
    final userId = account.signedIn ? next : null;
    if (userId == _requestedAccount) return;
    _requestedAccount = userId;
    final generation = ++_generation;
    _debounce?.cancel();
    _bindings = _bindings
        .catchError((Object _) {})
        .then((_) => _bind(userId, generation));
  }

  Future<void> _bind(String? userId, int generation) async {
    if (_disposed || generation != _generation) return;
    try {
      await controller.bindAccount(userId);
      if (_disposed || generation != _generation) return;
      final prefs = await SharedPreferences.getInstance();
      if (userId == null) {
        await prefs.remove('waybi_friends.last_account');
        _setStatus(FriendsBackupStatus.deviceOnly);
      } else {
        await prefs.setString('waybi_friends.last_account', userId);
        await sync();
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        _setStatus(FriendsBackupStatus.offline);
      }
    }
  }

  void _gameChanged() {
    if (_applying || !controller.ready || controller.accountId == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(sync()));
  }

  bool _sameAccount(String userId, int generation) =>
      !_disposed &&
      generation == _generation &&
      controller.accountId == userId &&
      account.signedIn &&
      account.profile?.id == userId;

  Future<void> sync() async {
    final userId = controller.accountId;
    final generation = _generation;
    if (_busy || userId == null || !_sameAccount(userId, generation)) return;
    _busy = true;
    _setStatus(FriendsBackupStatus.syncing);
    try {
      final prefs = await SharedPreferences.getInstance();
      final stampKey = '${controller.saveKey}.cloud_snapshot';
      for (var attempt = 0; attempt < 3; attempt++) {
        if (!_sameAccount(userId, generation)) return;
        int? revision;
        String? cursor;
        Map<String, dynamic>? remoteGame;
        int? updatedAt;
        final memories = <dynamic>[];
        final cursors = <String>{};
        var changedDuringRead = false;
        do {
          if (!_sameAccount(userId, generation)) return;
          final page = await account.readFriendsBackup(
            userId: userId,
            cursor: cursor,
          );
          if (!_sameAccount(userId, generation)) return;
          if (page['schemaVersion'] != 1 || page['revision'] is! int) {
            throw StateError('Unsupported Friends backup');
          }
          if (revision != null && revision != page['revision']) {
            changedDuringRead = true;
            break;
          }
          revision = page['revision'] as int;
          updatedAt = page['updatedAt'] as int?;
          final game = page['game'] as Map<String, dynamic>?;
          remoteGame ??= game;
          if (game != null) memories.addAll(game['memories'] as List);
          cursor = page['nextCursor'] as String?;
          if (cursor != null &&
              (!cursors.add(cursor) || cursors.length > 100)) {
            throw StateError('Invalid journal pagination');
          }
        } while (cursor != null);
        if (changedDuringRead) continue;
        final previousUpload = prefs.getString(stampKey);
        if (remoteGame != null) {
          final remote = SavedGame.decode(
            jsonEncode({...remoteGame, 'memories': memories}),
          );
          final untouched =
              controller.state.encode() == previousUpload ||
              (previousUpload == null &&
                  controller.state.memories.isEmpty &&
                  controller.state.activeJourney == null &&
                  controller.state.selectedItemIds.isEmpty);
          _applying = true;
          try {
            await controller.mergeCloudArchive(
              remote,
              preferCloudState: untouched,
              expectedAccountId: userId,
            );
          } finally {
            _applying = false;
          }
          if (!_sameAccount(userId, generation)) return;
          final canonicalRemote = remote
              .mergeArchive(const SavedGame())
              .encode();
          if (controller.state.encode() == canonicalRemote) {
            await prefs.setString(stampKey, canonicalRemote);
            lastBackupAt = updatedAt == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(updatedAt);
            _setStatus(FriendsBackupStatus.backedUp);
            return;
          }
        }
        if (!_sameAccount(userId, generation)) return;
        final snapshot = controller.state.encode();
        final game = jsonDecode(snapshot) as Map<String, dynamic>;
        final existingIds = memories.map((memory) => memory['id']).toSet();
        final existingTrips = memories
            .map((memory) => memory['sourceTripId'])
            .whereType<String>()
            .where((trip) => trip.isNotEmpty)
            .toSet();
        final missing = (game['memories'] as List)
            .where(
              (memory) =>
                  !existingIds.contains(memory['id']) &&
                  (memory['sourceTripId'] == null ||
                      !existingTrips.contains(memory['sourceTripId'])),
            )
            .toList();
        // Upload only new memories in bounded batches. A growing journal must
        // not re-upload its whole history or exceed the API body limit.
        Map<String, dynamic>? result;
        for (
          var offset = 0;
          offset < (missing.isEmpty ? 1 : missing.length);
          offset += 20
        ) {
          if (!_sameAccount(userId, generation)) return;
          result = await account.writeFriendsBackup(
            userId: userId,
            revision: revision!,
            game: {...game, 'memories': missing.skip(offset).take(20).toList()},
          );
          if (!_sameAccount(userId, generation)) return;
          if (result == null) break;
          revision = result['revision'] as int;
        }
        if (result == null) continue;
        await prefs.setString(stampKey, snapshot);
        if (!_sameAccount(userId, generation)) return;
        lastBackupAt = DateTime.fromMillisecondsSinceEpoch(
          result['updatedAt'] as int,
        );
        _setStatus(FriendsBackupStatus.backedUp);
        if (snapshot != controller.state.encode()) _gameChanged();
        return;
      }
      throw StateError('Friends backup changed during synchronization');
    } catch (_) {
      if (_sameAccount(userId, generation)) {
        _setStatus(FriendsBackupStatus.offline);
      }
    } finally {
      _busy = false;
      // A new account may have bound while an older request was in flight.
      if (!_disposed && generation != _generation) unawaited(sync());
    }
  }

  void _setStatus(FriendsBackupStatus next) {
    if (_disposed) return;
    status = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _debounce?.cancel();
    _retry?.cancel();
    account.removeListener(_accountChanged);
    controller.removeListener(_gameChanged);
    super.dispose();
  }
}
