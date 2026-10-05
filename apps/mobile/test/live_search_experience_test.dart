import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/providers/provider_contracts.dart';
import 'package:waybi_mobile/widgets/companion_search_prompt.dart';
import 'package:waybi_mobile/widgets/full_screen_search.dart';

class _FakeSearchProvider implements SearchProvider {
  int calls = 0;

  @override
  Future<List<PlaceCandidate>> search(
    String query, {
    GeoPoint? proximity,
    required String language,
  }) async {
    calls++;
    return [
      PlaceCandidate(
        name: '42 Verissimo Drive',
        address: 'Māngere, Auckland 2022, New Zealand',
        kind: PlaceKind.address,
        location: const GeoPoint(-36.984, 174.79),
        reference: const ProviderReference('test', '42-verissimo'),
      ),
    ];
  }
}

void main() {
  testWidgets('map search shows live suggestions without Enter', (
    tester,
  ) async {
    final opened = <String>[];
    final selected = <PlaceCandidate>[];
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanionSearchPrompt(
            marker: LocationMarkerStyle.kiwi,
            language: 'zh',
            currentLocation: const GeoPoint(-36.85, 174.76),
            onSearch: opened.add,
            loadSuggestions: (query) async {
              loads++;
              return const [
                PlaceCandidate(
                  name: '42 Verissimo Drive',
                  address: 'Māngere, Auckland 2022, New Zealand',
                  kind: PlaceKind.address,
                  location: GeoPoint(-36.984, 174.79),
                ),
              ];
            },
            onSuggestionSelected: selected.add,
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('companionSearchInput')),
      '42 veri',
    );
    await tester.pump(const Duration(milliseconds: 130));
    await tester.pump();

    expect(loads, 1);
    expect(opened, isEmpty);
    expect(find.text('42 Verissimo Drive'), findsOneWidget);

    await tester.tap(find.text('42 Verissimo Drive'));
    await tester.pump();
    expect(selected, hasLength(1));
  });

  testWidgets('full-screen search returns suggestions while typing', (
    tester,
  ) async {
    final provider = _FakeSearchProvider();
    await tester.pumpWidget(
      MaterialApp(
        home: FullScreenSearch(
          provider: provider,
          resolve: (candidate) async => candidate.toPlace(candidate.location!),
          language: 'zh',
          recent: const [],
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '42 verissimo');
    await tester.pump(const Duration(milliseconds: 170));
    await tester.pump();

    expect(provider.calls, 1);
    expect(find.text('42 Verissimo Drive'), findsOneWidget);
    expect(find.text('搜索联想'), findsOneWidget);
  });
}
