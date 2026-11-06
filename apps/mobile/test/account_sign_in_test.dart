import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:waybi_mobile/data/account_repository.dart';
import 'package:waybi_mobile/widgets/account_sign_in.dart';

class TestAccount extends AccountRepository {
  int requests = 0, verifications = 0, google = 0, apple = 0, passwords = 0;
  String? sentEmail, challengeId, enteredCode;
  bool fail = false, malformed = false, preferencesFail = false;
  int retryAfter = 60;
  Object? socialError;
  Completer<void>? pending;
  @override
  Future<Map<String, dynamic>> requestEmailCode(
    String email, {
    String language = 'en',
  }) async {
    requests++;
    sentEmail = email;
    if (pending != null) await pending!.future;
    if (fail) throw StateError('Delivery unavailable');
    return malformed
        ? {}
        : {'challengeId': 'challenge-$requests', 'retryAfter': retryAfter};
  }

  @override
  Future<void> authenticateWithEmailCode({
    required String email,
    required String challengeId,
    required String code,
    String language = 'en',
    bool voiceEnabled = true,
  }) async {
    verifications++;
    this.challengeId = challengeId;
    enteredCode = code;
    if (fail) throw StateError('Code is invalid or expired');
  }

  @override
  Future<void> authenticate(
    String email,
    String password, {
    required bool register,
  }) async {
    passwords++;
    expect(register, isFalse);
    if (fail) throw StateError('Invalid credentials');
  }

  @override
  Future<void> authenticateWithGoogle({bool link = false}) async {
    google++;
    if (socialError != null) throw socialError!;
  }

  @override
  Future<void> authenticateWithApple({
    bool link = false,
    String language = 'en',
  }) async {
    apple++;
    if (socialError != null) throw socialError!;
  }

  @override
  Future<void> updatePreferences({
    required String language,
    required bool voiceEnabled,
  }) async {
    if (preferencesFail) throw StateError('Offline');
  }
}

Future<void> mount(
  WidgetTester t,
  TestAccount account, {
  String language = 'en',
  VoidCallback? onSignedIn,
}) async {
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AccountSignIn(
            account: account,
            language: language,
            onSignedIn: onSignedIn,
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String text) async {
  await t.ensureVisible(find.text(text));
  await t.tap(find.text(text));
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'email flow validates, resends with a new challenge, verifies and permits changing email',
    (t) async {
      final account = TestAccount()..retryAfter = 0;
      addTearDown(account.dispose);
      var successes = 0;
      await mount(t, account, onSignedIn: () => successes++);
      await tap(t, 'Continue with email');
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(account.requests, 0);
      await t.enterText(
        find.byType(TextFormField).first,
        'driver@example.test',
      );
      await tap(t, 'Continue with email');
      expect(account.requests, 1);
      expect(find.text('Resend code'), findsOneWidget);
      await tap(t, 'Verify and continue');
      expect(find.text('Enter the six-digit code'), findsOneWidget);
      expect(account.verifications, 0);
      await tap(t, 'Resend code');
      expect(account.requests, 2);
      await t.enterText(find.byType(TextFormField).last, '123456');
      account.fail = true;
      await tap(t, 'Verify and continue');
      expect(find.text('Code is invalid or expired'), findsOneWidget);
      expect(successes, 0);
      account.fail = false;
      account.preferencesFail = true;
      await tap(t, 'Verify and continue');
      expect(account.challengeId, 'challenge-2');
      expect(account.enteredCode, '123456');
      expect(successes, 1);
      await tap(t, 'Change email');
      expect(find.text('6-digit code'), findsNothing);
      await tap(t, 'Sign in with a password');
      await tap(t, 'Sign in');
      expect(find.text('Enter your password'), findsOneWidget);
      await t.enterText(find.byType(TextFormField).last, 'long-password');
      await t.tap(find.byTooltip('Show or hide password'));
      await t.pump();
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(account.passwords, 1);
      await tap(t, 'Use an email code instead');
      expect(find.text('Password'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'delivery errors recover, malformed replies fail and duplicate taps stay locked',
    (t) async {
      final account = TestAccount()..fail = true;
      addTearDown(account.dispose);
      await mount(t, account);
      await t.enterText(find.byType(TextFormField), 'driver@example.test');
      await tap(t, 'Continue with email');
      expect(find.text('Delivery unavailable'), findsOneWidget);
      account.fail = false;
      account.malformed = true;
      await tap(t, 'Continue with email');
      expect(
        find.text('Could not request a code. Please try again.'),
        findsOneWidget,
      );
      account.malformed = false;
      account.pending = Completer<void>();
      await t.tap(find.text('Continue with email'));
      await t.pump();
      expect(find.text('Please wait…'), findsOneWidget);
      final google = t.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Continue with Google'),
      );
      expect(google.onPressed, isNull);
      expect(account.requests, 3);
      account.pending!.complete();
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 61));
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'Google and Apple use the same entry; cancellation is quiet and failures recover',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final account = TestAccount();
      addTearDown(account.dispose);
      var successes = 0;
      await mount(t, account, onSignedIn: () => successes++);
      await tap(t, 'Continue with Google');
      await tap(t, 'Continue with Apple');
      expect([account.google, account.apple, successes], [1, 1, 2]);
      account.socialError = GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      );
      await tap(t, 'Continue with Google');
      expect(
        find.text('Google sign-in failed. Please try again.'),
        findsNothing,
      );
      account.socialError = GoogleSignInException(
        code: GoogleSignInExceptionCode.unknownError,
      );
      await tap(t, 'Continue with Google');
      expect(
        find.text('Google sign-in failed. Please try again.'),
        findsOneWidget,
      );
      account.socialError = const SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.canceled,
        message: 'Cancelled',
      );
      await tap(t, 'Continue with Apple');
      expect(
        find.text('Apple sign-in failed. Please try again.'),
        findsNothing,
      );
      account.socialError = const SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.failed,
        message: 'Failed',
      );
      await tap(t, 'Continue with Apple');
      expect(
        find.text('Apple sign-in failed. Please try again.'),
        findsOneWidget,
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'Chinese entry provides localized policy links and reports a launch failure',
    (t) async {
      final urls = <String>[];
      var launches = true;
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch') {
          urls.add((call.arguments as Map)['url'] as String);
        }
        return launches;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final account = TestAccount()..fail = true;
      addTearDown(account.dispose);
      await mount(t, account, language: 'zh');
      await tap(t, '使用条款');
      await tap(t, '隐私政策');
      expect(urls, [
        'https://waybi.co/zh/terms/',
        'https://waybi.co/zh/privacy/',
      ]);
      launches = false;
      await tap(t, '隐私政策');
      expect(find.text('暂时无法继续，请检查输入或稍后重试。'), findsOneWidget);
      await t.enterText(find.byType(TextFormField), 'driver@example.test');
      await tap(t, '使用邮箱继续');
      expect(find.text('暂时无法继续，请检查输入或稍后重试。'), findsOneWidget);
    },
  );

  test('repository verifies through real HTTP boundary, requires a server cookie and stores no OTP', () async {
    FlutterSecureStorage.setMockInitialValues({});
    var status = 200, cookie = false;
    final requests = <http.Request>[];
    final account = AccountRepository(
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/auth/email/request') {
          return http.Response(
            jsonEncode({'challengeId': 'challenge', 'retryAfter': 60}),
            200,
          );
        }
        expect(request.url.path, '/api/auth/email/verify');
        return http.Response(
          jsonEncode(
            status == 200
                ? {
                    'user': {'id': 'driver', 'email': 'driver@example.test'},
                  }
                : {'error': 'Code expired'},
          ),
          status,
          headers: cookie
              ? {'set-cookie': 'waybi_session=${'a' * 64}; HttpOnly'}
              : {},
        );
      }),
    );
    addTearDown(account.dispose);
    expect(
      (await account.requestEmailCode(' driver@example.test '))['challengeId'],
      'challenge',
    );
    expect(jsonDecode(requests.first.body)['email'], 'driver@example.test');
    Future<void> verify() => account.authenticateWithEmailCode(
      email: 'driver@example.test',
      challengeId: 'challenge',
      code: '123456',
    );
    await expectLater(verify(), throwsStateError);
    expect(account.profile, isNull);
    expect(account.loading, isFalse);
    status = 401;
    await expectLater(verify(), throwsStateError);
    status = 200;
    cookie = true;
    await verify();
    expect(account.profile!.id, 'driver');
    expect(await const FlutterSecureStorage().readAll(), {
      'waybi_session': 'a' * 64,
    });
    expect(requests.last.headers['x-waybi-client'], 'mobile');
  });
}
