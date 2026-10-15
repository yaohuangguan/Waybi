import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:waybi_mobile/drive/location_permission_gate.dart';

void main() {
  test('startup, resume and navigation share one permission sheet', () async {
    final answer = Completer<PermissionStatus>();
    var requests = 0;
    final gate = LocationPermissionGate(
      read: () async => PermissionStatus.denied,
      request: () {
        requests++;
        return answer.future;
      },
    );
    final startup = gate.ensure();
    final resume = gate.ensure(requestPermission: false);
    final navigation = gate.ensure();
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
    answer.complete(PermissionStatus.granted);
    expect(
      await Future.wait([startup, resume, navigation]),
      everyElement(PermissionStatus.granted),
    );
  });

  test(
    'denial does not reopen permission on resume; a user retry can ask',
    () async {
      var requests = 0;
      final gate = LocationPermissionGate(
        read: () async => PermissionStatus.denied,
        request: () async => ++requests == 1
            ? PermissionStatus.denied
            : PermissionStatus.granted,
      );
      expect(await gate.ensure(), PermissionStatus.denied);
      for (var i = 0; i < 3; i++) {
        expect(
          await gate.ensure(requestPermission: false),
          PermissionStatus.denied,
        );
      }
      expect(requests, 1);
      expect(await gate.ensure(), PermissionStatus.granted);
      expect(requests, 2);
    },
  );

  test('settings-only permissions never request another OS sheet', () async {
    for (final access in [
      PermissionStatus.permanentlyDenied,
      PermissionStatus.restricted,
      PermissionStatus.granted,
      PermissionStatus.limited,
    ]) {
      final gate = LocationPermissionGate(
        read: () async => access,
        request: () async => throw StateError('Must not request'),
      );
      expect(await gate.ensure(), access);
    }
  });

  test('failed native requests release the gate for a later retry', () async {
    var calls = 0;
    final gate = LocationPermissionGate(
      read: () async => PermissionStatus.denied,
      request: () async {
        if (++calls == 1) throw StateError('Native service unavailable');
        return PermissionStatus.granted;
      },
    );
    await expectLater(gate.ensure(), throwsStateError);
    expect(await gate.ensure(), PermissionStatus.granted);
    expect(calls, 2);
  });
}
