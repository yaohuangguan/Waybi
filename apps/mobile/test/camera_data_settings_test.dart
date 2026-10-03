import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/data/account_repository.dart';
import 'package:waybi_mobile/data/camera_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/safety_camera.dart';
import 'package:waybi_mobile/widgets/profile_page.dart';

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

AccountProfile _profile(String plan) => AccountProfile(
  email: 'test@example.com',
  displayName: 'Test',
  providers: const ['password'],
  routes: const [],
  places: const [],
  reviews: const [],
  recentDestinations: const [],
  plan: plan,
);

Widget _page({
  required AccountRepository account,
  required Future<CameraSnapshot?> Function() onSync,
}) => MaterialApp(
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

    notifySafetyCameras: false,
    notifyRoadIncidents: false,
    notifyCommunityReports: false,
    notifySavedRouteDisruptions: false,
    onNotifySafetyCamerasChanged: (_) {},
    onNotifyRoadIncidentsChanged: (_) {},
    onNotifyCommunityReportsChanged: (_) {},
    onNotifySavedRouteDisruptionsChanged: (_) {},
    cameraSnapshot: _snapshot(3),
    onSyncCameraData: onSync,
  ),
);

void _compactPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  testWidgets('Plus user can manually sync NZTA camera data', (tester) async {
    _compactPhone(tester);
    final account = AccountRepository()..profile = _profile('plus');
    addTearDown(account.dispose);
    var syncCalls = 0;

    await tester.pumpWidget(
      _page(
        account: account,
        onSync: () async {
          syncCalls++;
          return _snapshot(4, added: 1);
        },
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
    await tester.tap(syncButton);
    await tester.pumpAndSettle();

    expect(syncCalls, 1);
    expect(find.text('4 个公开固定摄像头'), findsOneWidget);
    expect(find.text('最近变化：+1 / -0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('free user keeps automatic data but manual sync is Plus-locked', (
    tester,
  ) async {
    _compactPhone(tester);
    final account = AccountRepository()..profile = _profile('free');
    addTearDown(account.dispose);
    var syncCalls = 0;

    await tester.pumpWidget(
      _page(
        account: account,
        onSync: () async {
          syncCalls++;
          return _snapshot(4, added: 1);
        },
      ),
    );
    await tester.pumpAndSettle();

    final locked = find.text('Plus · 检查摄像头更新');
    await tester.scrollUntilVisible(
      locked,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('3 个公开固定摄像头'), findsOneWidget);
    expect(find.textContaining('后台自动更新仍然对所有用户开放'), findsOneWidget);
    final buttonFinder = find.ancestor(
      of: locked,
      matching: find.byType(FilledButton),
    );
    final button = tester.widget<FilledButton>(buttonFinder);
    expect(button.onPressed, isNull);
    expect(syncCalls, 0);
  });
}
