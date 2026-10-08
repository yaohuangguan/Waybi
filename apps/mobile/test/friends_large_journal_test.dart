import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_friends/waybi_friends.dart';
import 'package:waybi_mobile/data/friends_backup_service.dart';

import 'friends_backup_service_test.dart' show FakeAccount, memory;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a large recovered journal uploads in bounded batches and later room changes send no old memories', () async {
    SharedPreferences.setMockInitialValues({
      'journal': SavedGame(
        memories: List.generate(65, (index) => memory('old-$index')),
      ).encode(),
    });
    final game = GameController(saveKey: 'journal');
    final account = FakeAccount()..select('alice');
    final backup = FriendsBackupService(account, controller: game);
    addTearDown(() {
      backup.dispose();
      game.dispose();
      account.dispose();
    });
    await backup.start();
    expect(backup.status, FriendsBackupStatus.backedUp);
    expect(account.batchSizes, [20, 20, 20, 5]);
    expect(account.saves['alice']!['game']['memories'], hasLength(65));
    await game.changeScene(HomeScene.garden);
    await backup.sync();
    expect(account.batchSizes.last, 0);
    expect(account.saves['alice']!['game']['memories'], hasLength(65));
  });
}
