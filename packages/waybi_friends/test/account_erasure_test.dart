import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_friends/waybi_friends.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('deleting account erases only its journal, backups and sync snapshots', () async {
    final game = GameController(saveKey: 'waybi_release_test');
    await game.bindAccount('deleted-user');
    final prefs = await SharedPreferences.getInstance();
    const deleted = 'waybi_release_test.account.deleted-user';
    const retained = 'waybi_release_test.account.retained-user';
    await prefs.setString('$deleted.cloud_snapshot', 'private cloud receipt');
    await prefs.setString('$deleted.pending_restore', 'private pending restore');
    await prefs.setString(retained, 'other-account-data');
    await prefs.setString('$retained.backup', 'other-account-backup');

    await game.eraseDeletedAccount('deleted-user');

    for (final key in [
      deleted,
      '$deleted.backup',
      '$deleted.pending_restore',
      '$deleted.cloud_snapshot',
    ]) {
      expect(prefs.containsKey(key), false, reason: key);
    }
    expect(prefs.getString(retained), 'other-account-data');
    expect(prefs.getString('$retained.backup'), 'other-account-backup');
    expect(game.accountId, isNull);
  });
}
