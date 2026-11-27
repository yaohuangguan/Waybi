import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_friends/waybi_friends.dart';
import 'package:waybi_mobile/data/friends_backup_service.dart';

import 'friends_backup_service_test.dart' show FakeAccount, memory;

class CountingAccount extends FakeAccount {
  int reads = 0;
  @override
  Future<Map<String, dynamic>> readFriendsBackup({
    required String userId,
    String? cursor,
  }) {
    reads++;
    return super.readFriendsBackup(userId: userId, cursor: cursor);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'an unchanged journal is confirmed with one page, not re-downloaded',
    () async {
      final game = GameController(saveKey: 'journal');
      final account = CountingAccount()..select('alice');
      var navigating = false;
      final backup = FriendsBackupService(
        account,
        controller: game,
        deferWhile: () => navigating,
      );
      addTearDown(() {
        backup.dispose();
        game.dispose();
        account.dispose();
      });
      await backup.start();
      expect(backup.status, FriendsBackupStatus.backedUp);
      final reads = account.reads;
      final writes = account.writes.length;
      await backup.syncIfNeeded();
      expect(account.reads, reads, reason: 'Nothing changed locally');
      await backup.sync();
      expect(
        account.reads,
        reads + 1,
        reason: 'One page confirms the revision',
      );
      expect(account.writes, hasLength(writes));
      expect(backup.status, FriendsBackupStatus.backedUp);

      // A new memory uploads alone, without downloading the journal.
      await game.rememberArrival(
        tripId: 'trip-2',
        destinationName: 'Harbour',
        countryCode: 'NZ',
      );
      await backup.sync();
      expect(account.reads, reads + 2);
      expect(account.batchSizes.last, 1);
      expect(account.saves['alice']!['game']['memories'], hasLength(1));

      // While navigating, syncing waits for the trip to end.
      navigating = true;
      await game.rememberArrival(
        tripId: 'trip-3',
        destinationName: 'Beach',
        countryCode: 'NZ',
      );
      await backup.sync();
      expect(account.reads, reads + 2);
      navigating = false;
      await backup.syncIfNeeded();
      expect(account.saves['alice']!['game']['memories'], hasLength(2));

      // Another device wrote: the revision moved, so the journal is merged.
      account.saves['alice']!['revision'] =
          (account.saves['alice']!['revision'] as int) + 1;
      (account.saves['alice']!['game']['memories'] as List).add(
        (jsonDecode(SavedGame(memories: [memory('other-device')]).encode())
            as Map<String, dynamic>)['memories'][0],
      );
      await backup.sync();
      expect(game.state.memories.map((m) => m.id), contains('other-device'));
    },
  );
}
