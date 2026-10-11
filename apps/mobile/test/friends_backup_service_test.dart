import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_friends/waybi_friends.dart';
import 'package:waybi_mobile/data/account_repository.dart';
import 'package:waybi_mobile/data/friends_backup_service.dart';

class FakeAccount extends AccountRepository {
  final saves = <String, Map<String, dynamic>>{};
  bool disconnected = false;
  bool conflictOnce = false;
  Completer<Map<String, dynamic>>? delayed;
  final writes = <String>[];
  final batchSizes = <int>[];
  @override
  bool get signedIn => profile != null;
  void select(String? id) {
    profile = id == null
        ? null
        : AccountProfile.fromJson({
            'user': {'id': id},
          });
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> readFriendsBackup({
    required String userId,
    String? cursor,
  }) async {
    if (disconnected) throw StateError('Offline');
    if (delayed case final pending?) {
      delayed = null;
      return pending.future;
    }
    return saves[userId] ??
        {'schemaVersion': 1, 'revision': 0, 'game': null, 'nextCursor': null};
  }

  @override
  Future<Map<String, dynamic>?> writeFriendsBackup({
    required String userId,
    required int revision,
    required Map<String, dynamic> game,
  }) async {
    if (disconnected) throw StateError('Offline');
    if (conflictOnce) {
      conflictOnce = false;
      saves[userId] = page(
        SavedGame(memories: [memory('other-device')]),
        revision: revision + 1,
      );
      return null;
    }
    if (revision != (saves[userId]?['revision'] ?? 0)) return null;
    writes.add(userId);
    batchSizes.add((game['memories'] as List).length);
    final merged = SavedGame.decode(jsonEncode(game)).mergeArchive(
      SavedGame.decode(jsonEncode(saves[userId]?['game'] ?? const {})),
    );
    saves[userId] = {
      'schemaVersion': 1,
      'revision': revision + 1,
      'game': jsonDecode(merged.encode()),
      'updatedAt': 1791400000000,
      'nextCursor': null,
    };
    return saves[userId]!;
  }
}

JourneyMemory memory(String id) => JourneyMemory(
  id: id,
  destinationId: 'mission_bay',
  returnedAt: DateTime.utc(2026, 10, 8),
  itemIds: const [],
  title: id,
  story: 'A journey',
  souvenir: 'A postcard',
);
Map<String, dynamic> page(SavedGame game, {int revision = 1}) => {
  'schemaVersion': 1,
  'revision': revision,
  'game': jsonDecode(game.encode()),
  'updatedAt': 1791400000000,
  'nextCursor': null,
};
Future<void> settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 10, 8, 1);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('first account adopts the recovered journal once; logout and another account stay separate', () async {
    SharedPreferences.setMockInitialValues({
      'journal': SavedGame(memories: [memory('recovered')]).encode(),
    });
    final game = GameController(saveKey: 'journal', clock: () => now);
    final account = FakeAccount()..select('alice');
    final backup = FriendsBackupService(account, controller: game);
    addTearDown(() {
      backup.dispose();
      game.dispose();
      account.dispose();
    });
    await backup.start();
    expect(backup.status, FriendsBackupStatus.backedUp);
    expect(
      account.saves['alice']!['game']['memories'].single['id'],
      'recovered',
    );
    account.select(null);
    await settle();
    expect(game.state.memories, isEmpty);
    account.select('bob');
    await settle();
    expect(game.state.memories, isEmpty);
    expect(account.saves['bob']!['game']['memories'], isEmpty);
    account.select('alice');
    await settle();
    expect(game.state.memories.single.id, 'recovered');
    final prefs = await SharedPreferences.getInstance();
    expect(
      SavedGame.decode(prefs.getString('journal.pre_account')!)
          .memories
          .single
          .id,
      'recovered',
    );
  });

  test('a new phone restores souvenirs and an active outing; stale completed outings are not resurrected', () async {
    final active = ActiveJourney(
      destinationId: 'mission_bay',
      departedAt: now,
      returnAt: now.add(const Duration(hours: 5)),
      itemIds: const ['camera'],
      traveller: FriendKind.sett,
    );
    final account = FakeAccount()..select('alice');
    account.saves['alice'] = page(
      SavedGame(
        activeJourney: active,
        roomLife: RoomLife(startedAt: now).departing(now, FriendKind.sett),
        memories: [memory('cloud-memory')],
      ),
    );
    final game = GameController(saveKey: 'journal', clock: () => now);
    final backup = FriendsBackupService(account, controller: game);
    addTearDown(() {
      backup.dispose();
      game.dispose();
      account.dispose();
    });
    await backup.start();
    expect(game.state.activeJourney!.traveller, FriendKind.sett);
    expect(game.state.memories.single.id, 'cloud-memory');
    final completed = game.engine.finish(active, at: active.returnAt);
    await game.mergeCloudArchive(
      SavedGame(activeJourney: active, memories: [completed]),
      expectedAccountId: 'alice',
    );
    expect(game.state.activeJourney, isNull);
    expect(game.state.memories, hasLength(2));
  });

  test('offline changes remain local and a conflict merges both devices before retrying', () async {
    final account = FakeAccount()
      ..select('alice')
      ..disconnected = true;
    final game = GameController(saveKey: 'journal', clock: () => now);
    final backup = FriendsBackupService(account, controller: game);
    addTearDown(() {
      backup.dispose();
      game.dispose();
      account.dispose();
    });
    await backup.start();
    await game.rememberArrival(
      tripId: 'my-trip',
      destinationName: 'Harbour',
      countryCode: 'NZ',
    );
    await backup.sync();
    expect(backup.status, FriendsBackupStatus.offline);
    expect(game.state.memories, hasLength(1));
    account
      ..disconnected = false
      ..conflictOnce = true;
    await backup.sync();
    expect(backup.status, FriendsBackupStatus.backedUp);
    expect(
      game.state.memories.map((m) => m.id),
      containsAll(['navigation:my-trip', 'other-device']),
    );
    expect(account.saves['alice']!['game']['memories'], hasLength(2));
  });

  test('a delayed response from a previous account cannot restore or upload its journal to the next account', () async {
    final delayed = Completer<Map<String, dynamic>>();
    final account = FakeAccount()
      ..select('alice')
      ..delayed = delayed;
    final game = GameController(saveKey: 'journal', clock: () => now);
    final backup = FriendsBackupService(account, controller: game);
    addTearDown(() {
      backup.dispose();
      game.dispose();
      account.dispose();
    });
    final starting = backup.start();
    await settle();
    account.select('bob');
    await settle();
    delayed.complete(page(SavedGame(memories: [memory('alice-private')])));
    await starting;
    await settle();
    expect(game.accountId, 'bob');
    expect(game.state.memories, isEmpty);
    expect(account.writes, isNot(contains('alice')));
    expect(account.saves['bob']!['game']['memories'], isEmpty);
  });
}
