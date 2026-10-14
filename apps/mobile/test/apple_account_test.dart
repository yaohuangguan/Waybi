import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/data/account_repository.dart';
import 'package:waybi_mobile/data/apple_sign_in.dart';

class FakeApple implements AppleSignInGateway {
  int calls = 0;
  @override
  Future<Map<String, String>> authorize() async {
    calls++;
    return {
      'identityToken': 'signed-token',
      'authorizationCode': 'one-use-code',
      'rawNonce': 'n' * 64,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'Apple config failure never opens native consent or changes session',
    () async {
      final gateway = FakeApple();
      final account = AccountRepository(
        appleSignIn: gateway,
        client: MockClient((r) async => http.Response('{"ready":false}', 200)),
      );
      addTearDown(account.dispose);
      await expectLater(account.authenticateWithApple(), throwsStateError);
      expect(gateway.calls, 0);
      expect(account.loading, false);
      expect(account.signedIn, false);
    },
  );
  test('Apple credentials need a verified backend session before becoming signed in', () async {
    const token =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final gateway = FakeApple();
    final account = AccountRepository(
      appleSignIn: gateway,
      client: MockClient((r) async {
        if (r.url.path.endsWith('/config')) {
          return http.Response('{"ready":true}', 200);
        }
        expect(r.url.path, '/api/auth/apple');
        expect(r.headers['x-waybi-client'], 'mobile');
        final body = jsonDecode(r.body) as Map;
        expect(body['authorizationCode'], 'one-use-code');
        expect(body['rawNonce'], 'n' * 64);
        return http.Response(
          jsonEncode({
            'user': {
              'email': 'relay@privaterelay.appleid.com',
              'providers': ['apple'],
            },
          }),
          200,
          headers: {'set-cookie': 'waybi_session=$token; HttpOnly'},
        );
      }),
    );
    addTearDown(account.dispose);
    await account.authenticateWithApple(language: 'zh');
    expect(account.signedIn, true);
    expect(account.profile!.providers, ['apple']);
    expect(
      await const FlutterSecureStorage().read(key: 'waybi_session'),
      token,
    );
    expect(account.loading, false);
  });
  test(
    'Apple rejection leaves the existing session intact and can be retried',
    () async {
      const token =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      FlutterSecureStorage.setMockInitialValues({'waybi_session': token});
      final gateway = FakeApple();
      final account = AccountRepository(
        appleSignIn: gateway,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/me')) {
            return http.Response(
              '{"user":{"email":"existing@waybi.test"}}',
              200,
            );
          }
          if (r.url.path.endsWith('/config')) {
            return http.Response('{"ready":true}', 200);
          }
          expect(r.url.path, '/api/auth/apple/link');
          return http.Response(
            '{"error":"Apple account is linked elsewhere"}',
            409,
          );
        }),
      );
      addTearDown(account.dispose);
      await account.restore();
      await expectLater(
        account.authenticateWithApple(link: true),
        throwsStateError,
      );
      expect(account.sessionToken, token);
      expect(account.profile!.email, 'existing@waybi.test');
      expect(account.loading, false);
    },
  );
}
