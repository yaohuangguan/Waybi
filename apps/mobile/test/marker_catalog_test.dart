import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_layer_settings.dart';
import 'package:waybi_mobile/providers/camera_marker_art.dart';
import 'package:waybi_mobile/providers/destination_marker_art.dart';
import 'package:waybi_mobile/widgets/map_symbols.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'all camera types produce decodable distinct route and map markers',
    () async {
      final badges = <String>{};
      for (final kind in CameraKind.values) {
        badges.add(CameraMarkerArt.badge(kind));
        final map = await CameraMarkerArt.png(kind, onRoute: false);
        final route = await CameraMarkerArt.png(kind, onRoute: true);
        expect(map, isNot(orderedEquals(route)));
        final codec = await ui.instantiateImageCodec(map);
        final frame = await codec.getNextFrame();
        expect([frame.image.width, frame.image.height], [92, 104]);
        frame.image.dispose();
        codec.dispose();
        expect(
          identical(await CameraMarkerArt.png(kind, onRoute: false), map),
          isTrue,
        );
      }
      expect(badges.length, CameraKind.values.length);
    },
  );
  test('destination marker decodes and failed native symbol registration remains retryable', () async {
    final bytes = await DestinationMarkerArt.png();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    expect([frame.image.width, frame.image.height], [96, 112]);
    frame.image.dispose();
    codec.dispose();
    expect(identical(await DestinationMarkerArt.png(), bytes), isTrue);
    expect(MapSymbols.camera(CameraKind.spotSpeed, onRoute: true), isNull);
    await expectLater(
      MapSymbols.ensureRegistered(),
      throwsA(isA<UnimplementedError>()),
    );
    await expectLater(
      MapSymbols.ensureRegistered(),
      throwsA(isA<UnimplementedError>()),
    );
  });
}
