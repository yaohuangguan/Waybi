import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_lens_mobile/domain/map_provider.dart';
import 'package:kiwi_lens_mobile/domain/map_layer_settings.dart';
import 'package:kiwi_lens_mobile/providers/independent_map_renderer.dart';
import 'package:kiwi_lens_mobile/providers/provider_contracts.dart';
import 'package:kiwi_lens_mobile/widgets/kiwi_mascot.dart';

void main() {
  testWidgets(
    'pinch pauses following and preserves zoom across GPS ticks; deck padding keeps the puck visible',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      var following = true;
      var bottom = 215.0;
      MapRenderer? renderer;
      StateSetter? update;
      const location = GeoPoint(-36.8485, 174.7633);
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, state) {
              update = state;
              return Scaffold(
                body: IndependentMapRenderer(
                  initialViewport: const MapViewportState(
                    center: location,
                    zoom: 17,
                  ),
                  layers: const MapLayerSettings(),
                  locationMarker: LocationMarkerStyle.kiwi,
                  locationEnabled: true,
                  following: following,
                  moving: true,
                  language: 'zh',
                  location: location,
                  heading: 45,
                  contentPadding: EdgeInsets.fromLTRB(16, 180, 16, bottom),
                  cameras: const [],
                  onCamera: (_) {},
                  roadEvents: const [],
                  onRoadEvent: (_) {},
                  route: const [],
                  selectedPlace: null,
                  explorePlaces: const [],
                  onExplorePlace: (_) {},
                  onReady: (map) {
                    renderer = map;
                    map.moveTo(map.viewport);
                  },
                  onViewportChanged: (_) {},
                  onMapPlace: (_) {},
                  onBlankTap: () {},
                  onUserPan: () => state(() => following = false),
                  styleLoader: ({required dark, required language}) async =>
                      throw StateError('Offline map style'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);
      final a = await tester.startGesture(const Offset(60, 340), pointer: 1);
      final b = await tester.startGesture(const Offset(320, 500), pointer: 2);
      await a.moveTo(const Offset(140, 380));
      await b.moveTo(const Offset(240, 450));
      await tester.pump(const Duration(milliseconds: 100));
      await a.up();
      await b.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(following, false);
      final zoom = renderer!.viewport.zoom;
      expect(zoom, lessThan(17));
      // The application only moves the map on a GPS tick when following is on.
      for (var i = 0; i < 3; i++) {
        if (following) {
          await renderer!.moveTo(renderer!.viewport.copyWith(center: location));
        }
        await tester.pump(const Duration(seconds: 1));
      }
      expect(renderer!.viewport.zoom, zoom);
      update!(() {
        following = true;
        bottom = 370;
      });
      await tester.pump();
      await tester.pump();
      final puck = tester.getCenter(find.byType(KiwiMascot));
      expect(puck.dy, greaterThan(180 + 22));
      expect(puck.dy, lessThan(844 - bottom - 22));
      expect(renderer!.viewport.zoom, zoom);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
