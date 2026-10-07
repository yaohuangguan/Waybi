import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/providers/place_search_providers.dart';

final _address = {
  'id': 'address-completion',
  'provider': 'derived:address-interpolation',
  'name': '42 Verissimo Drive',
  'address': '42 Verissimo Drive, Auckland, New Zealand',
  'latitude': -36.99, 'longitude': 174.789,
  'isPoi': false, 'interpolated': true, 'approximate': true,
};
const _auckland = GeoPoint(-36.8576, 174.7633);

void main() {
  test('valid partial address response beyond the old 1.8s cutoff is kept without a serial fallback', () async {
    var calls = 0;
    final provider = IndependentSearchProvider(
      useWorkerSuggestions: true,
      requestSpacing: Duration.zero,
      client: MockClient((request) async {
        calls++;
        expect(request.url.path, '/api/suggest');
        expect(request.url.queryParameters['q'], '42 veri');
        expect(request.url.queryParameters['provider'], 'independent');
        await Future<void>.delayed(const Duration(milliseconds: 1900));
        return http.Response(jsonEncode([_address]), 200);
      }),
    );
    addTearDown(provider.dispose);
    final results = await provider.search('42 veri', proximity: _auckland, language: 'en');
    expect(calls, 1);
    expect(results.single.name, '42 Verissimo Drive');
    expect(results.single.category, isEmpty);
    expect(results.single.kind, PlaceKind.address);
  });

  test('cached full address supplies immediate shorter prefixes within the same language and area', () async {
    var calls = 0;
    final provider = IndependentSearchProvider(
      useWorkerSuggestions: true,
      client: MockClient((request) async {
        calls++;
        return http.Response(jsonEncode([_address]), 200);
      }),
    );
    addTearDown(provider.dispose);
    await provider.search('42 verissimo drive', proximity: _auckland, language: 'en');
    final cached = provider.cachedSuggestions('42 veri', proximity: _auckland, language: 'en');
    expect(cached.single.name, '42 Verissimo Drive');
    expect(calls, 1);
    expect(provider.cachedSuggestions('43 veri', proximity: _auckland, language: 'en'), isEmpty);
    expect(provider.cachedSuggestions('42 veri', proximity: _auckland, language: 'zh'), isEmpty);
    expect(provider.cachedSuggestions('42 veri', proximity: const GeoPoint(-33.86, 151.21), language: 'en'), isEmpty);
  });

  test('Worker fallback keeps the selected map provider and empty responses do not poison the cache', () async {
    final requests = <Uri>[];
    final provider = WorkerSearchProvider(mapCompatible: true, client: MockClient((request) async {
      requests.add(request.url);
      expect(request.url.queryParameters['provider'], 'independent');
      return http.Response(jsonEncode(requests.length <= 2 ? [] : [_address]), 200);
    }));
    addTearDown(provider.dispose);
    expect(await provider.search('42 veri', proximity: _auckland, language: 'en'), isEmpty);
    expect(requests.map((url) => url.path), ['/api/suggest', '/api/search']);
    expect(await provider.search('42 veri', proximity: _auckland, language: 'en'), hasLength(1));
    expect(requests, hasLength(3));
  });
}
