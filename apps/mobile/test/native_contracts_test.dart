import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/data/apple_sign_in.dart';
import 'package:waybi_mobile/drive/device_heading.dart';
import 'package:waybi_mobile/services/native_map_language.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const apple = MethodChannel('com.aboutyou.dart_packages.sign_in_with_apple');
  const language = MethodChannel('waybi/map_language');
  tearDown(() {
    messenger.setMockMethodCallHandler(apple, null);
    messenger.setMockMethodCallHandler(language, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('waybi/device_heading'),
      null,
    );
    debugDefaultTargetPlatformOverride = null;
  });
  test(
    'native Apple consent uses distinct state and a hashed random nonce',
    () async {
      final sent = <Map>[];
      messenger.setMockMethodCallHandler(apple, (call) async {
        expect(call.method, 'performAuthorizationRequest');
        final request = (call.arguments as List).single as Map;
        sent.add(request);
        return {
          'type': 'appleid',
          'state': request['state'],
          'authorizationCode': 'one-use-code',
          'identityToken': 'signed-token',
          'givenName': 'Waybi',
          'familyName': 'Driver',
        };
      });
      final gateway = NativeAppleSignInGateway();
      final first = await gateway.authorize();
      final second = await gateway.authorize();
      expect(first['rawNonce'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(
        sent.first['nonce'],
        sha256.convert(utf8.encode(first['rawNonce']!)).toString(),
      );
      expect(sent.first['nonce'], isNot(first['rawNonce']));
      expect(sent.first['state'], isNot(sent.last['state']));
      expect(first['rawNonce'], isNot(second['rawNonce']));
      expect(first['fullName'], 'Waybi Driver');
      expect(first.containsKey('state'), isFalse);
    },
  );
  for (final fault in ['state', 'token', 'code']) {
    test('native Apple consent rejects invalid $fault', () async {
      messenger.setMockMethodCallHandler(apple, (call) async {
        final request = (call.arguments as List).single as Map;
        return {
          'type': 'appleid',
          'state': fault == 'state' ? 'replayed' : request['state'],
          'authorizationCode': fault == 'code' ? '' : 'code',
          'identityToken': fault == 'token' ? null : 'token',
        };
      });
      await expectLater(
        NativeAppleSignInGateway().authorize(),
        throwsStateError,
      );
    });
  }
  test('native map locale handles unavailable plugins and forwards system settings', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(await NativeMapLanguage.apply('zh'), isFalse);
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(language, (call) async {
      calls.add(call);
      return call.method == 'setLanguage' ? true : null;
    });
    expect(await NativeMapLanguage.apply('zh'), isTrue);
    await NativeMapLanguage.openSettings();
    expect(calls.map((c) => c.method), ['setLanguage', 'openSettings']);
    expect(calls.first.arguments, 'zh');
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(await NativeMapLanguage.apply('en'), isTrue);
    expect(calls, hasLength(2));
  });
  test('heading stream rejects malformed native values and releases the subscription', () async {
    const name = 'waybi/device_heading';
    const codec = StandardMethodCodec();
    final nativeCalls = <String>[];
    messenger.setMockMethodCallHandler(const MethodChannel(name), (call) async {
      nativeCalls.add(call.method);
      return null;
    });
    final readings = <double>[];
    final errors = <Object>[];
    final subscription = DeviceHeading.readings.listen(
      readings.add,
      onError: errors.add,
    );
    await Future<void>.delayed(Duration.zero);
    for (final value in [42, -1, 360, double.nan, 'invalid']) {
      ServicesBinding.instance.channelBuffers.push(
        name,
        codec.encodeSuccessEnvelope(
          value == 'invalid' ? value : {'heading': value},
        ),
        (_) {},
      );
    }
    await Future<void>.delayed(Duration.zero);
    expect(readings, [42]);
    expect(errors, hasLength(4));
    expect(errors.every((e) => e is FormatException), isTrue);
    await subscription.cancel();
    expect(nativeCalls, ['listen', 'cancel']);
  });
}
