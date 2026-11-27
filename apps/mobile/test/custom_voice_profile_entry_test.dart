import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/data/account_repository.dart';
import 'package:waybi_mobile/data/plus_billing.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/drive/custom_voice.dart';
import 'package:waybi_mobile/widgets/custom_voice_page.dart';
import 'package:waybi_mobile/widgets/plus_page.dart';
import 'package:waybi_mobile/widgets/profile_page.dart';

class _Billing extends PlusBillingGateway {
  @override
  Future<PlusOffering> load() async => const PlusOffering(
    available: false,
    provider: PlusBillingProvider.apple,
    plans: [],
  );
  @override
  Future<void> subscribe(PlusPlan plan) async {}
  @override
  Future<void> restore() async {}
  @override
  Future<void> manage() async {}
}

Widget _page(AccountRepository account, CustomVoiceController voice) =>
    MaterialApp(
      home: ProfilePage(
        account: account,
        plusBilling: _Billing(),
        customVoice: voice,
        voiceEnabled: true,
        lanesEnabled: true,
        appLanguage: 'en',
        voiceLanguage: 'en-NZ',
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
        onSyncCameraData: () async => null,
      ),
    );

void main() {
  late Directory root;
  late CustomVoiceController voice;
  late AccountRepository account;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('waybi-voice-entry-');
    voice = CustomVoiceController(rootDirectory: () async => root);
    account = AccountRepository();
  });
  tearDown(() {
    voice.dispose();
    account.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  final entry = find.byKey(const ValueKey('custom-voice-entry'));
  Future<void> reveal(WidgetTester tester) => tester.scrollUntilVisible(
    entry,
    200,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 50,
  );
  Future<void> openEntry(WidgetTester tester) async {
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
  }

  testWidgets('free users get the Plus upsell from the voice entry', (
    tester,
  ) async {
    await tester.pumpWidget(_page(account, voice));
    await reveal(tester);
    expect(find.text('Plus · guidance in your own voice'), findsOneWidget);
    await openEntry(tester);
    expect(find.byType(PlusPage), findsOneWidget);
    expect(find.byType(CustomVoicePage), findsNothing);
  });

  testWidgets('Plus members open the recording page', (tester) async {
    voice.setPlus(true);
    await tester.pumpWidget(_page(account, voice));
    await reveal(tester);
    expect(find.text('Record phrases in your own voice'), findsOneWidget);
    await openEntry(tester);
    expect(find.byType(CustomVoicePage), findsOneWidget);
  });
}
