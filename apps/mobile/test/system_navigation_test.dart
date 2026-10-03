import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/drive/system_navigation.dart';
import 'package:waybi_mobile/drive/location_feed_owner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/system_navigation');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'background GPS starts only after the foreground stream is released',
    () async {
      final cancellation = Completer<void>();
      final controller = StreamController<int>(
        onCancel: () => cancellation.future,
      );
      final owner = LocationFeedOwner()
        ..subscription = controller.stream.listen((_) {});
      var backgroundStarted = false;
      final switched = owner.release().then((_) => backgroundStarted = true);
      await Future<void>.delayed(Duration.zero);
      expect(owner.subscription, isNull);
      expect(backgroundStarted, isFalse);
      cancellation.complete();
      await switched;
      expect(backgroundStarted, isTrue);
      await controller.close();
    },
  );

  test(
    'trip stop discards old queued GPS updates and closes the surface',
    () async {
      final calls = <String>[];
      final opening = Completer<bool>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'start') return opening.future;
        return true;
      });
      final navigation = SystemNavigation(channel: channel);
      final started = navigation.start({'instruction': 'Head north'});
      await Future<void>.delayed(Duration.zero);
      final pending = navigation.update({'instruction': 'Turn right'});
      final stopped = navigation.stop();
      opening.complete(true);
      await Future.wait([started, pending, stopped]);
      expect(calls, ['start', 'stop']);
      await navigation.update({'instruction': 'Late fix'});
      expect(calls, ['start', 'stop']);
    },
  );

  test(
    'new turns and rerouting reach the system surface without throttle delay',
    () async {
      final instructions = <Object?>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        instructions.add((call.arguments as Map)['instruction']);
        return true;
      });
      var now = DateTime(2026, 10, 3);
      final navigation = SystemNavigation(channel: channel, clock: () => now);
      await navigation.start({'instruction': 'Continue'});
      await navigation.update({'instruction': 'Continue'});
      await navigation.update({'instruction': 'Continue'});
      await navigation.update({'instruction': 'Turn left'});
      await navigation.update({
        'instruction': 'Updating route',
        'offRoute': true,
      });
      expect(instructions, [
        'Continue',
        'Continue',
        'Turn left',
        'Updating route',
      ]);
      now = now.add(const Duration(seconds: 3));
      await navigation.update({
        'instruction': 'Updating route',
        'offRoute': true,
      });
      expect(instructions, hasLength(5));
    },
  );
}
