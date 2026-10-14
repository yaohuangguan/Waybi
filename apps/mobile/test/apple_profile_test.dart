import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/data/account_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/widgets/profile_page.dart';

Widget page(AccountRepository account) => MaterialApp(
  home: ProfilePage(
    account: account,
    voiceEnabled: true,
    lanesEnabled: true,
    appLanguage: 'en',
    voiceLanguage: 'en-NZ',
    onVoiceChanged: (_) {},
    onLanesChanged: (_) {},
    onAppLanguageChanged: (_) {},
    onLanguageChanged: (_) {},
    onMapLayers: () {},
    mapProvider: MapProvider.independent,
    locationMarker: LocationMarkerStyle.kiwi,
    onMapProviderChanged: (p) async => p,
    onLocationMarkerChanged: (_) {},
    notifySafetyCameras: false,
    notifyRoadIncidents: false,
    notifyCommunityReports: false,
    notifySavedRouteDisruptions: false,
    onNotifySafetyCamerasChanged: (_) {},
    onNotifyRoadIncidentsChanged: (_) {},
    onNotifyCommunityReportsChanged: (_) {},
    onNotifySavedRouteDisruptionsChanged: (_) {},
    onSyncCameraData: () async => null,
  ),
);

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'Google stays available while Apple is offered only on iOS ($platform)',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final account = AccountRepository();
          addTearDown(account.dispose);
          await tester.pumpWidget(page(account));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Continue with Google'),
            150,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Continue with Google'), findsOneWidget);
          expect(
            find.byKey(const Key('appleSignInButton')),
            platform == TargetPlatform.iOS ? findsOneWidget : findsNothing,
          );
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
  testWidgets(
    'existing Google user can explicitly link Apple without losing Google',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final account = AccountRepository()
          ..profile = AccountProfile.fromJson({
            'user': {
              'id': 'test',
              'email': 'existing@waybi.test',
              'providers': ['google'],
            },
          });
        addTearDown(account.dispose);
        await tester.pumpWidget(page(account));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Link Apple account'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Link Apple account'), findsOneWidget);
        expect(find.text('Link Google account'), findsNothing);
        expect(account.profile!.providers, ['google']);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
