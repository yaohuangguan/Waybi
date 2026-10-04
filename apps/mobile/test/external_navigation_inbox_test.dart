import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/services/external_navigation_inbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/external_navigation');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> signalPending() async {
    final complete = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('pending')),
      (_) => complete.complete(),
    );
    await complete.future;
  }

  test('holds a cold-start URL until map/onboarding consumes it', () async {
    String? native = 'waybi://navigate?destination=Newmarket';
    messenger.setMockMethodCallHandler(channel, (_) async {
      final result = native;
      native = null;
      return result;
    });
    final inbox = ExternalNavigationInbox(channel);
    await inbox.start();
    expect(inbox.hasPending, isTrue);
    expect(inbox.takePending(), contains('Newmarket'));
    expect(inbox.takePending(), isNull);
    inbox.dispose();
  });

  test('a warm URL replaces an unconsumed startup destination', () async {
    String? native = 'waybi://navigate?destination=First';
    messenger.setMockMethodCallHandler(channel, (_) async {
      final result = native;
      native = null;
      return result;
    });
    final inbox = ExternalNavigationInbox(channel);
    await inbox.start();
    native = 'waybi://navigate?destination=Second';
    await signalPending();
    expect(inbox.takePending(), contains('Second'));
    inbox.dispose();
  });

  test(
    'arrival during initial handoff is drained without losing the newer URL',
    () async {
      final first = Completer<String?>();
      int calls = 0;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async =>
            ++calls == 1 ? first.future : 'waybi://navigate?destination=Newer',
      );
      final inbox = ExternalNavigationInbox(channel);
      final starting = inbox.start();
      await Future<void>.delayed(Duration.zero);
      await signalPending();
      first.complete('waybi://navigate?destination=Older');
      await starting;
      expect(calls, 2);
      expect(inbox.takePending(), contains('Newer'));
      inbox.dispose();
    },
  );

  test('platforms without the iOS bridge can still start normally', () async {
    final inbox = ExternalNavigationInbox(channel);
    await inbox.start();
    expect(inbox.hasPending, isFalse);
    inbox.dispose();
  });
}
