import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/providers/place_search_providers.dart';
import 'package:waybi_mobile/providers/provider_contracts.dart';
import 'package:waybi_mobile/widgets/full_screen_search.dart';

class _DelayedSearch implements SearchProvider {
  final queries = <String>[];
  final pending = <Completer<List<PlaceCandidate>>>[];

  @override
  Future<List<PlaceCandidate>> search(
    String query, {
    GeoPoint? proximity,
    required String language,
  }) {
    queries.add(query);
    final completer = Completer<List<PlaceCandidate>>();
    pending.add(completer);
    return completer.future;
  }
}

void main() {
  for (final provider in MapProvider.values) {
    test(
      '$provider declares capabilities and consistent provider identities',
      () {
        final policy = ProviderPolicy(provider);
        final google = provider == MapProvider.google;
        final capabilities = policy.capabilities;
        expect(capabilities.trafficAwareRouting, google);
        expect(capabilities.nativeTurnGuidance, google);
        expect(capabilities.transitRouting, isTrue);
        expect(capabilities.persistProviderPlaces, isTrue);
        expect(policy.searchProvider, google ? 'geoapify' : 'osm');
        expect(policy.placeProvider, google ? 'google' : 'osm');
        expect(policy.routingProvider, google ? 'google' : 'independent');
        expect(policy.navigationEngine, policy.routingProvider);
        expect(policy.canDisplay(null), isTrue);
        expect(
          policy.canDisplay(const ProviderReference('at', 'parking')),
          isTrue,
        );
      },
    );
  }
  test('place selections retain their source and origin renderer through every entry point', () {
    final place = PlaceSummary(
      name: 'Home',
      location: const GeoPoint(-37, 174),
    );
    for (final source in SelectionSource.values) {
      final selected = SelectedPlace(
        place,
        source,
        originMap: MapProvider.independent,
      );
      expect(selected.place, same(place));
      expect(selected.source, source);
      expect(selected.originMap, MapProvider.independent);
    }
  });

  test('provider references do not silently cross map policies', () {
    const google = ProviderPolicy(MapProvider.google);
    const independent = ProviderPolicy(MapProvider.independent);
    expect(google.canDisplay(const ProviderReference('google', 'g1')), isTrue);
    expect(
      google.canDisplay(const ProviderReference('independent', 'm1')),
      isFalse,
    );
    expect(
      independent.canDisplay(const ProviderReference('osm', 'm1')),
      isTrue,
    );
    expect(
      independent.canDisplay(const ProviderReference('here', 'h1')),
      isTrue,
    );
    expect(
      independent.canDisplay(const ProviderReference('google', 'g1')),
      isFalse,
    );
    for (final provider in [
      'geoapify',
      'tomtom',
      'regional:linz-nz-addresses',
      'derived:address-interpolation',
    ]) {
      expect(
        independent.canDisplay(
          ProviderReference(provider, 'independent-result'),
        ),
        isTrue,
        reason:
            '$provider must remain usable when Google map/search is disabled',
      );
    }
  });

  test('street addresses retain their exact first line', () {
    const address = PlaceCandidate(
      name: '18 Queen Street',
      address: '18 Queen Street, Auckland CBD, Auckland 1010',
      kind: PlaceKind.address,
    );
    expect(address.secondaryAddress, 'Auckland CBD, Auckland 1010');
    expect(
      address.toPlace(const GeoPoint(-36.844, 174.766)).name,
      '18 Queen Street',
    );
  });

  testWidgets('search waits 160 ms and ignores stale responses', (
    tester,
  ) async {
    final provider = _DelayedSearch();
    await tester.pumpWidget(
      MaterialApp(
        home: FullScreenSearch(
          provider: provider,
          resolve: (candidate) async => candidate.toPlace(candidate.location!),
          language: 'en',
          recent: const [],
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Cordis');
    await tester.pump(const Duration(milliseconds: 159));
    expect(provider.queries, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(provider.queries, ['Cordis']);

    await tester.enterText(find.byType(TextField), 'Cordis Auckland');
    await tester.pump(const Duration(milliseconds: 160));
    expect(provider.queries, ['Cordis', 'Cordis Auckland']);

    provider.pending.first.complete(const [
      PlaceCandidate(name: 'Old result', location: GeoPoint(-36.8, 174.7)),
    ]);
    await tester.pump();
    expect(find.text('Old result'), findsNothing);

    provider.pending.last.complete(const [
      PlaceCandidate(
        name: 'Cordis Auckland',
        address: '83 Symonds Street, Grafton, Auckland',
        location: GeoPoint(-36.856, 174.764),
      ),
    ]);
    await tester.pump();
    expect(find.widgetWithText(ListTile, 'Cordis Auckland'), findsOneWidget);
    expect(find.text('83 Symonds Street, Grafton, Auckland'), findsOneWidget);
  });

  test(
    'Practice search uses a global OSM geocoder without paid keys',
    () async {
      final requests = <Uri>[];
      final provider = IndependentSearchProvider(
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            '{"features":[{"geometry":{"coordinates":[114.51,38.04]},"properties":{"name":"石家庄市","osm_type":"R","osm_id":912940,"city":"石家庄市"}}]}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(provider.dispose);
      final results = await provider.search(
        '石家庄',
        proximity: const GeoPoint(-36.8485, 174.7633),
        language: 'zh',
      );
      expect(results.single.name, '石家庄市');
      expect(results.single.location, const GeoPoint(38.04, 114.51));
      expect(results.single.reference?.provider, 'osm');
      expect(requests, hasLength(2));
      expect(
        requests.every((request) => request.host == 'photon.komoot.io'),
        isTrue,
      );
      expect(requests.first.queryParameters.containsKey('bbox'), isTrue);
      expect(requests.last.queryParameters.containsKey('bbox'), isFalse);
      expect(
        requests.every(
          (request) => !request.queryParameters.containsKey('access_token'),
        ),
        isTrue,
      );
    },
  );
}
