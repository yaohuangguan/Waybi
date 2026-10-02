import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_lens_mobile/data/account_repository.dart';
import 'package:kiwi_lens_mobile/data/plus_billing.dart';
import 'package:kiwi_lens_mobile/widgets/plus_page.dart';

class TestAccount extends AccountRepository {
  TestAccount({this.loggedIn = true}) {
    if (loggedIn) setPlan('free');
  }
  bool loggedIn;
  bool? syncedVoice;
  void setPlan(String plan) {
    profile = AccountProfile(
      email: 'driver@example.test',
      displayName: '',
      providers: [],
      routes: [],
      places: [],
      reviews: [],
      recentDestinations: [],
      plan: plan,
    );
    notifyListeners();
  }

  @override
  bool get signedIn => loggedIn;
  @override
  Future<void> refresh() async {}
  @override
  Future<void> authenticate(
    String email,
    String password, {
    required bool register,
  }) async {
    loggedIn = true;
    setPlan('free');
  }

  @override
  Future<void> updatePreferences({
    required String language,
    required bool voiceEnabled,
  }) async {
    syncedVoice = voiceEnabled;
    throw StateError('Preference sync unavailable after successful login');
  }
}

class TestBilling extends PlusBillingGateway {
  TestBilling({this.available = true});
  final bool available;
  String? purchased;
  bool fail = false;
  @override
  Future<PlusOffering> load() async => PlusOffering(
    available: available,
    provider: PlusBillingProvider.apple,
    canRestore: true,
    plans: const [
      PlusPlan(
        id: 'monthly',
        price: r'NZ$4.99',
        amount: 4.99,
        currency: 'NZD',
        annual: false,
      ),
      PlusPlan(
        id: 'annual',
        price: r'NZ$39.99',
        amount: 39.99,
        currency: 'NZD',
        annual: true,
      ),
    ],
  );
  @override
  Future<void> subscribe(PlusPlan plan) async {
    if (fail) throw StateError('Not verified');
    purchased = plan.id;
  }

  @override
  Future<void> restore() async {}
  @override
  Future<void> manage() async {}
}

void main() {
  void size(WidgetTester tester) {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets(
    'native Plus retains selected monthly plan and does not grant unverified access',
    (tester) async {
      size(tester);
      final account = TestAccount();
      final billing = TestBilling();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(375, 667),
              textScaler: TextScaler.linear(1.3),
            ),
            child: PlusPage(account: account, language: 'zh', billing: billing),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('提前一点，\n从容一点。'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('plus-plan-monthly')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('plus-plan-monthly')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plus-subscribe')));
      await tester.pumpAndSettle();
      expect(billing.purchased, 'monthly');
      expect(account.profile?.isPlus, false);
      expect(find.textContaining('完成付款后返回这里'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('unavailable billing keeps the paid action disabled', (
    tester,
  ) async {
    size(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: PlusPage(
          account: TestAccount(),
          language: 'en',
          billing: TestBilling(available: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('plus-subscribe')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Subscriptions opening soon'), findsOneWidget);
  });
  testWidgets(
    'guest signs in within Plus and keeps the selected plan even if preference sync fails',
    (tester) async {
      size(tester);
      final account = TestAccount(loggedIn: false);
      final billing = TestBilling();
      await tester.pumpWidget(
        MaterialApp(
          home: PlusPage(
            account: account,
            language: 'en',
            voiceEnabled: false,
            billing: billing,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('plus-plan-monthly')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('plus-plan-monthly')));
      await tester.tap(find.byKey(const ValueKey('plus-subscribe')));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back.'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).first,
        'driver@example.test',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        'sample-password',
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back.'), findsNothing);
      expect(account.syncedVoice, false);
      expect(find.text('Subscribe to Plus'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('plus-subscribe')));
      await tester.pumpAndSettle();
      expect(billing.purchased, 'monthly');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'account upgrades update membership in place and stop another purchase',
    (tester) async {
      size(tester);
      final account = TestAccount();
      await tester.pumpWidget(
        MaterialApp(
          home: PlusPage(
            account: account,
            language: 'zh',
            billing: TestBilling(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      account.setPlan('plus');
      await tester.pumpAndSettle();
      expect(find.text('Plus 已启用'), findsOneWidget);
      expect(find.text('订阅 Plus'), findsNothing);
      expect(find.text('回到地图，出发吧'), findsOneWidget);
    },
  );
  testWidgets(
    'active manual member can return from Plus through Account to the map',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final account = TestAccount()..setPlan('plus');
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Free map')),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Account')),
        ),
      );
      await tester.pumpAndSettle();
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => PlusPage(
            account: account,
            language: 'zh',
            billing: TestBilling(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plus-subscribe')));
      await tester.pumpAndSettle();
      expect(find.text('Free map'), findsOneWidget);
      expect(find.text('Account'), findsNothing);
      expect(find.text('Kiwi Lens Plus'), findsNothing);
    },
  );
}
