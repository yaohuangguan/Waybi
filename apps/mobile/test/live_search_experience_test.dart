import 'dart:async';

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
  testWidgets('map dropdown scrolls through every result above the keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selected = <PlaceCandidate>[];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(viewInsets: const EdgeInsets.only(bottom: 300)),
          child: child!,
        ),
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                top: 8,
                left: 16,
                right: 16,
                child: CompanionSearchPrompt(
                  marker: LocationMarkerStyle.kiwi,
                  language: 'en',
                  onSearch: (_) {},
                  loadSuggestions: (_) async => List.generate(
                    12,
                    (index) => PlaceCandidate(
                      name: 'Result $index',
                      address: 'Canterbury, New Zealand',
                      kind: PlaceKind.address,
                      location: const GeoPoint(-43.53, 172.64),
                    ),
                  ),
                  onSuggestionSelected: selected.add,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('companionSearchInput')),
      'christchurch',
    );
    await tester.pump(const Duration(milliseconds: 130));
    await tester.pump();
    final scrollable = find.descendant(
      of: find.byKey(const Key('mapSearchSuggestions')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Result 11'),
      150,
      scrollable: scrollable,
    );
    await tester.tap(find.text('Result 11'));
    await tester.pump();
    expect(selected.single.name, 'Result 11');
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting a cached result cancels a pending dropdown update', (
    tester,
  ) async {
    final pending = Completer<List<PlaceCandidate>>();
    const cached = PlaceCandidate(
      name: 'Christchurch',
      kind: PlaceKind.address,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanionSearchPrompt(
            marker: LocationMarkerStyle.kiwi,
            language: 'en',
            onSearch: (_) {},
            cachedSuggestions: (_) => [cached],
            loadSuggestions: (_) => pending.future,
            onSuggestionSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('companionSearchInput')),
      'christchurch',
    );
    await tester.pump(const Duration(milliseconds: 130));
    await tester.tap(find.text('Christchurch'));
    pending.complete([
      const PlaceCandidate(name: 'Late result', kind: PlaceKind.address),
    ]);
    await tester.pump();
    expect(find.text('Late result'), findsNothing);
    expect(find.byKey(const Key('mapSearchSuggestions')), findsNothing);
  });

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
