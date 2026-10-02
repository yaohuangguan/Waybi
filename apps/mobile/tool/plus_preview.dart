// Preview the production Flutter pages with explicit sample data, without GPS or payments.
// flutter run -d web-server --target tool/plus_preview.dart --web-port 5181
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:kiwi_lens_mobile/data/account_repository.dart';
import 'package:kiwi_lens_mobile/data/plus_billing.dart';
import 'package:kiwi_lens_mobile/domain/map_provider.dart';
import 'package:kiwi_lens_mobile/theme/kiwi_lens_theme.dart';
import 'package:kiwi_lens_mobile/widgets/plus_page.dart';
import 'package:kiwi_lens_mobile/widgets/trips_page.dart';

class PreviewAccount extends AccountRepository {
  PreviewAccount() {
    profile = const AccountProfile(
      email: 'driver@example.test',
      displayName: 'Kiwi',
      providers: [],
      routes: [],
      places: [],
      reviews: [],
      recentDestinations: [],
      plan: 'free',
    );
  }
  @override
  bool get signedIn => true;
  @override
  Future<void> refresh() async {}
}

class PreviewBilling extends PlusBillingGateway {
  @override
  Future<PlusOffering> load() async => const PlusOffering(
    provider: PlusBillingProvider.apple,
    available: false,
    plans: [
      PlusPlan(
        id: 'monthly',
        price: 'NZ\$4.99',
        amount: 4.99,
        currency: 'NZD',
        annual: false,
      ),
      PlusPlan(
        id: 'annual',
        price: 'NZ\$39.99',
        amount: 39.99,
        currency: 'NZD',
        annual: true,
      ),
    ],
  );
  @override
  Future<void> subscribe(PlusPlan plan) async {}
  @override
  Future<void> restore() async {}
  @override
  Future<void> manage() async {}
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  runApp(const PlusPreview());
}

class PlusPreview extends StatefulWidget {
  const PlusPreview({super.key});
  @override
  State<PlusPreview> createState() => _PlusPreviewState();
}

class _PlusPreviewState extends State<PlusPreview> {
  final account = PreviewAccount();
  String language = 'zh';
  bool trips = false, dark = false;
  @override
  void dispose() {
    account.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark
        ? KiwiLensTheme.darkFor(language)
        : KiwiLensTheme.lightFor(language),
    locale: Locale(language),
    supportedLocales: const [Locale('en'), Locale('zh')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Column(
      children: [
        Material(
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'Flutter · sample UI',
                    style: TextStyle(fontSize: 10),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () =>
                      setState(() => language = language == 'zh' ? 'en' : 'zh'),
                  child: Text(language == 'zh' ? 'EN' : '中文'),
                ),
                IconButton(
                  onPressed: () => setState(() => dark = !dark),
                  icon: const Icon(Icons.dark_mode_outlined),
                ),
                TextButton(
                  onPressed: () => setState(() => trips = !trips),
                  child: Text(trips ? 'Plus' : 'Trips'),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: trips
              ? TripsPage(
                  language: language,
                  loader: () async => TripsSnapshot(
                    signedIn: true,
                    isPlus: true,
                    quickPlaces: const {
                      'Work': TripDestination(
                        name: 'Work',
                        location: GeoPoint(-36.87, 174.77),
                      ),
                    },
                    quickRoutes: const {},
                    recent: const [],
                    history: [
                      for (final (name, mode) in [
                        ('Mission Bay', 'drive'),
                        ('Auckland Library', 'walking'),
                        ('Newmarket', 'drive'),
                      ])
                        TripHistoryItem(
                          destination: TripDestination(
                            name: name,
                            location: const GeoPoint(-36.85, 174.76),
                          ),
                          mode: mode,
                          distanceMeters: 7800,
                          durationSeconds: 900,
                          createdAt: DateTime.now(),
                        ),
                    ],
                  ),
                )
              : PlusPage(
                  account: account,
                  language: language,
                  billing: PreviewBilling(),
                ),
        ),
      ],
    ),
  );
}
