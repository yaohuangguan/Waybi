import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/data/account_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'legacy login migrates once and cannot return after offline sign-out',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'kiwi_lens_session': 'legacy-token',
      });
      const storage = FlutterSecureStorage();
      final account = AccountRepository(
        storage: storage,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/logout')) {
            throw http.ClientException('Offline');
          }
          expect(request.headers['cookie'], 'waybi_session=legacy-token');
          return http.Response(
            jsonEncode({
              'user': {'email': 'person@example.test'},
            }),
            200,
          );
        }),
      );
      addTearDown(account.dispose);
      await account.restore();
      expect(account.signedIn, isTrue);
      expect(await storage.read(key: 'waybi_session'), 'legacy-token');
      expect(await storage.read(key: 'kiwi_lens_session'), isNull);
      await account.signOut();
      await account.restore();
      expect(account.signedIn, isFalse);
      expect(await storage.read(key: 'waybi_session'), isNull);
    },
  );

  test('expired new login clears both identities without falling back to an old session', () async {
    FlutterSecureStorage.setMockInitialValues({
      'waybi_session': 'expired',
      'kiwi_lens_session': 'old',
    });
    const storage = FlutterSecureStorage();
    final account = AccountRepository(
      storage: storage,
      client: MockClient((request) async {
        expect(request.headers['cookie'], 'waybi_session=expired');
        return http.Response('{}', 401);
      }),
    );
    addTearDown(account.dispose);
    await account.restore();
    expect(account.signedIn, isFalse);
    expect(await storage.read(key: 'waybi_session'), isNull);
    expect(await storage.read(key: 'kiwi_lens_session'), isNull);
  });
}
