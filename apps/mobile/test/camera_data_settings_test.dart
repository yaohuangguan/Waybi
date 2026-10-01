import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_lens_mobile/data/account_repository.dart';
import 'package:kiwi_lens_mobile/data/camera_repository.dart';
import 'package:kiwi_lens_mobile/domain/map_provider.dart';
import 'package:kiwi_lens_mobile/domain/safety_camera.dart';
import 'package:kiwi_lens_mobile/widgets/profile_page.dart';

CameraSnapshot _snapshot(int count, {int added = 0}) {
  final cameras = <SafetyCamera>[];
  for (var index = 0; index < count; index++) {
    final type = switch (index % 3) {
      0 => 'Spot speed',
      1 => 'Red light',
      _ => 'Average speed',
    };
    cameras.add(
      SafetyCamera(
        id: 'camera-$index',
        name: 'Camera $index',
        region: 'Auckland',
        suburb: 'CBD',
        location: 'Test Road $index',
        type: type,
        latitude: -36.85 - index * .001,
        longitude: 174.76 + index * .001,
      ),
    );
  }
  return CameraSnapshot(
    cameras: cameras,
    syncStatus: 'live',
    sourceUpdatedAt: DateTime.utc(2026, 10, 1),
    checkedAt: DateTime.utc(2026, 10, 2),
    fetchMode: 'reader-fallback',
    changeAdded: added,
  );
}

void main() {
  testWidgets('settings shows NZTA camera freshness and manual sync result', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final account = AccountRepository();
    addTearDown(account.dispose);
    var syncCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(
          account: account,
          voiceEnabled: true,
          lanesEnabled: true,
          appLanguage: 'zh',
          voiceLanguage: 'zh-CN',
          onVoiceChanged: (_) {},
          onLanesChanged: (_) {},
          onAppLanguageChanged: (_) {},
          onLanguageChanged: (_) {},
          onMapLayers: () {},
          mapProvider: MapProvider.google,
          locationMarker: LocationMarkerStyle.kiwi,
          onMapProviderChanged: (value) async => value,
          onLocationMarkerChanged: (_) {},
          mapboxAvailable: false,
          notifySafetyCameras: false,
          notifyRoadIncidents: false,
          notifyCommunityReports: false,
          notifySavedRouteDisruptions: false,
          onNotifySafetyCamerasChanged: (_) {},
          onNotifyRoadIncidentsChanged: (_) {},
          onNotifyCommunityReportsChanged: (_) {},
          onNotifySavedRouteDisruptionsChanged: (_) {},
          cameraSnapshot: _snapshot(3),
          onSyncCameraData: () async {
            syncCalls++;
            return _snapshot(4, added: 1);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final syncButton = find.text('检查摄像头更新');
    await tester.scrollUntilVisible(
      syncButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('3 个公开固定摄像头'), findsOneWidget);
    expect(find.text('定点 1'), findsOneWidget);
    expect(find.text('红灯 1'), findsOneWidget);
    expect(find.text('区间 1'), findsOneWidget);
    expect(find.text('NZTA 页面校验回退'), findsOneWidget);

    await tester.tap(syncButton);
    await tester.pumpAndSettle();

    expect(syncCalls, 1);
    expect(find.text('4 个公开固定摄像头'), findsOneWidget);
    expect(find.text('最近变化：+1 / -0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
