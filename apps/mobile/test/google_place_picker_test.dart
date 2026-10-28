import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/providers/provider_contracts.dart';
import 'package:waybi_mobile/services/google_place_picker.dart';
import 'package:waybi_mobile/widgets/full_screen_search.dart';

class _FreeSearch implements SearchProvider {
  final queries = <String>[];
  @override
  Future<List<PlaceCandidate>> search(
    String query, {
    GeoPoint? proximity,
    required String language,
  }) async {
    queries.add(query);
    return [
      const PlaceCandidate(
        name: '16 Queen Street',
        address: 'Ōtāhuhu, Auckland',
        kind: PlaceKind.address,
        location: GeoPoint(-36.94, 174.84),
        reference: ProviderReference('osm', 'node/1'),
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(GooglePlacePicker.channel, null);
  });
  for (final selected in [true, false]) {
    testWidgets(
      'Google first selection=$selected; quota fallback stays in free search',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final provider = _FreeSearch();
        var googleCalls = 0;
        PlaceSummary? picked;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(GooglePlacePicker.channel, (_) async {
              googleCalls++;
              return jsonEncode({
                'status': selected ? 'selected' : 'fallback',
                'id': 'selected-id',
                'latitude': -36.94,
                'longitude': 174.84,
                'query': '16 Queen Street, Ōtāhuhu',
              });
            });
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    picked = await Navigator.of(context).push<PlaceSummary>(
                      MaterialPageRoute(
                        builder: (_) => FullScreenSearch(
                          provider: provider,
                          resolve: (candidate) async => PlaceSummary(
                            name: candidate.name,
                            location: candidate.location!,
                            reference: candidate.reference,
                          ),
                          language: 'en',
                          recent: const [],
                          initialQuery: '16 Queen Street',
                          preferGoogle: true,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(googleCalls, 1);
        if (selected) {
          expect(picked?.reference?.id, 'selected-id');
          expect(provider.queries, isEmpty);
        } else {
          expect(provider.queries, ['16 Queen Street, Ōtāhuhu']);
          expect(find.text('16 Queen Street'), findsOneWidget);
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
          expect(googleCalls, 1);
          expect(provider.queries.length, 2);
          await tester.tap(find.text('16 Queen Street'));
          await tester.pumpAndSettle();
          expect(picked?.reference?.provider, 'osm');
        }
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
  test(
    'UI Kit returns only a valid selected coordinate and the user query',
    () async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(GooglePlacePicker.channel, (call) async {
            captured = call;
            return jsonEncode({
              'status': 'selected',
              'id': 'google-place-id',
              'latitude': -36.94,
              'longitude': 174.84,
              'query': 'Queen Street, Otahuhu',
            });
          });
      final result = await GooglePlacePicker.open(
        query: 'Queen Street',
        language: 'zh',
        near: const GeoPoint(-36.85, 174.77),
      );
      final uri = Uri.parse((captured!.arguments as Map)['url'] as String);
      expect(uri.origin, 'https://waybi.co');
      expect(uri.path, '/api/search/google');
      expect(uri.queryParameters['near'], '174.77,-36.85');
      expect(result.place!.location.latitude, -36.94);
      expect(result.place!.name, 'Queen Street, Otahuhu');
      expect(result.place!.reference!.provider, 'google-ui-kit');
      expect(result.place!.address, isEmpty);
      expect(
        const ProviderPolicy(MapProvider.independent)
            .canDisplay(result.place!.reference),
        isTrue,
      );
      expect(
        const ProviderPolicy(
          MapProvider.independent,
        ).canDisplay(const ProviderReference('google', 'ordinary-places-api')),
        isFalse,
      );
    },
  );
  test(
    'unsupported desktops use the free provider without a native call',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(GooglePlacePicker.supported, isFalse);
      expect(
        (await GooglePlacePicker.open(query: 'address', language: 'en')).place,
        isNull,
      );
    },
  );
  for (final data in [
    {'status': 'fallback', 'query': 'User edited query'},
    {'status': 'selected', 'id': '', 'latitude': -36.94, 'longitude': 174.84},
    {'status': 'selected', 'id': 'id', 'latitude': 91, 'longitude': 174.84},
    {
      'status': 'selected',
      'id': 'id',
      'latitude': 'invalid',
      'longitude': 174.84,
    },
    {
      'status': 'selected',
      'id': 'id',
      'latitude': -36.94,
      'longitude': 174.84,
      'query': '',
    },
    {
      'status': 'selected',
      'id': 'id',
      'latitude': -36.94,
      'longitude': 174.84,
      'query': 'x' * 121,
    },
    {
      'status': 'selected',
      'id': 'x' * 257,
      'latitude': -36.94,
      'longitude': 174.84,
    },
  ]) {
    test(
      'invalid or unavailable selection falls back: ${data['id'] ?? data['status']} ${data['latitude']}',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              GooglePlacePicker.channel,
              (_) async => jsonEncode(data),
            );
        final result = await GooglePlacePicker.open(
          query: 'Original query',
          language: 'en',
        );
        expect(result.place, isNull);
        expect(result.cancelled, isFalse);
      },
    );
  }
  test('dismissing the picker preserves cancellation and malformed replies recover', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(GooglePlacePicker.channel, (_) async => null);
    expect(
      (await GooglePlacePicker.open(query: 'query', language: 'en')).cancelled,
      isTrue,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          GooglePlacePicker.channel,
          (_) async => 'not json',
        );
    expect(
      (await GooglePlacePicker.open(query: 'query', language: 'en')).query,
      'query',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          GooglePlacePicker.channel,
          (_) async => throw PlatformException(code: 'offline'),
        );
    expect(
      (await GooglePlacePicker.open(query: 'query', language: 'en')).place,
      isNull,
    );
  });
}
