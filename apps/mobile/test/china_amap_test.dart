import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/domain/china_region.dart';
import 'package:waybi_mobile/domain/far_match.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/drive/navigation_language.dart';
import 'package:waybi_mobile/providers/independent_routing_provider.dart';
import 'package:waybi_mobile/providers/place_search_providers.dart';
import 'package:waybi_mobile/providers/provider_contracts.dart';
import 'package:waybi_mobile/widgets/companion_search_prompt.dart';
import 'package:waybi_mobile/widgets/far_match_notice.dart';
import 'package:waybi_mobile/widgets/full_screen_search.dart';
import 'package:waybi_mobile/widgets/place_details_content.dart';
import 'package:waybi_mobile/widgets/place_sources_sheet.dart';
import 'package:waybi_mobile/widgets/route_preview_sheet.dart';

const shijiazhuang = GeoPoint(38.04, 114.51);

/// What /api/suggest returns near Shijiazhuang (see the Worker's Amap tests).
final amapSuggestions = [
  {
    'id': 'B0FFHQ1A2B',
    'provider': 'amap',
    'name': '盛世春天',
    'address': '河北省石家庄市长安区建华北大街与北二环东路交叉口东北',
    'label': '盛世春天, 河北省石家庄市长安区建华北大街与北二环东路交叉口东北',
    'isPoi': true,
    'resultType': '住宅小区',
    'latitude': 38.0602,
    'longitude': 114.5206,
    'distanceMeters': 2382,
    'attribution': amapAttribution,
  },
  {
    'id': 'B017309XYZ',
    'provider': 'amap',
    'name': '盛世春天',
    'address': '河南省漯河市源汇区嵩山路与黄河路交叉口',
    'isPoi': true,
    'resultType': '住宅小区',
    'latitude': 33.5815,
    'longitude': 114.0166,
    'distanceMeters': 497000,
  },
];

PlaceCandidate candidate(
  String name,
  GeoPoint location, {
  String category = '',
  PlaceKind kind = PlaceKind.poi,
  String provider = 'amap',
}) => PlaceCandidate(
  name: name,
  location: location,
  category: category,
  kind: kind,
  reference: ProviderReference(provider, name),
);

class _ListSearch implements SearchProvider {
  _ListSearch(this.results);
  final List<PlaceCandidate> results;
  @override
  Future<List<PlaceCandidate>> search(
    String query, {
    GeoPoint? proximity,
    required String language,
  }) async => results;
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('mainland China region', () {
    test('matches the Worker for boundary neighbours', () {
      for (final point in const [
        shijiazhuang,
        GeoPoint(22.5431, 114.0579), // Shenzhen
        GeoPoint(22.2707, 113.5767), // Zhuhai
        GeoPoint(24.4798, 118.0894), // Xiamen
        GeoPoint(20.03, 110.33), // Haikou
        GeoPoint(43.8256, 87.6168), // Urumqi
      ]) {
        expect(isMainlandChina(point), isTrue, reason: '$point');
      }
      for (final point in const [
        GeoPoint(22.284, 114.1589), // Hong Kong
        GeoPoint(22.1987, 113.5439), // Macau
        GeoPoint(24.4321, 118.3171), // Kinmen
        GeoPoint(26.16, 119.94), // Matsu
        GeoPoint(25.03, 121.56), // Taipei
        GeoPoint(37.57, 126.98), // Seoul
        GeoPoint(21.03, 105.85), // Hanoi
        GeoPoint(-36.85, 174.76), // Auckland
      ]) {
        expect(isMainlandChina(point), isFalse, reason: '$point');
      }
      expect(isMainlandChina(null), isFalse);
      expect(isMainlandChinaCoordinate(double.nan, 114), isFalse);
    });
  });

  group('far matches', () {
    test('the nearest named match decides, cities never warn', () {
      const luohe = GeoPoint(33.5815, 114.0166);
      expect(
        farMatchDistance([candidate('盛世春天', luohe)], shijiazhuang),
        greaterThan(490000),
      );
      expect(
        farMatchDistance([
          candidate('盛世春天', luohe),
          candidate('盛世春天', const GeoPoint(38.0602, 114.5206)),
        ], shijiazhuang),
        isNull,
      );
      expect(
        farMatchDistance([
          candidate('北京市', const GeoPoint(39.9, 116.4), category: 'city'),
          candidate('北京饭店', const GeoPoint(39.9, 116.41)),
        ], shijiazhuang),
        isNull,
      );
      expect(
        farMatchDistance([
          candidate('Pin', luohe, kind: PlaceKind.coordinate),
        ], shijiazhuang),
        isNull,
      );
      expect(farMatchDistance([candidate('x', luohe)], null), isNull);
      expect(farMatchTitle(494400, 'zh'), '最近的匹配在 494 公里外');
      expect(farMatchTitle(494400, 'en'), 'Nearest match is 494 km away');
      expect(farMatchDetail('zh'), contains('城市'));
      expect(farMatchDetail('en'), contains('city'));
      expect(farDestinationTitle(494400, 'zh'), '该地点在 494 公里外');
      expect(farDestinationTitle(494400, 'en'), 'This place is 494 km away');
      expect(farDestinationDetail('en'), contains('Check'));
      expect(farDestinationDetail('zh'), contains('确认'));
      expect(
        farDestinationDistance(
          const PlaceSummary(name: '石家庄', location: luohe, category: 'city'),
          shijiazhuang,
        ),
        isNull,
      );
      expect(
        farDestinationDistance(
          const PlaceSummary(name: '盛世春天', location: luohe),
          shijiazhuang,
        ),
        greaterThan(490000),
      );
      expect(
        farDestinationDistance(
          const PlaceSummary(name: 'x', location: luohe),
          null,
        ),
        isNull,
      );
    });
  });

  group('search in mainland China', () {
    test('uses Waybi Search (Amap) only, never public Photon', () async {
      final hosts = <String>[];
      final provider = IndependentSearchProvider(
        requestSpacing: Duration.zero,
        client: MockClient((request) async {
          hosts.add(request.url.host);
          expect(request.url.path, '/api/suggest');
          return http.Response(
            jsonEncode(amapSuggestions),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final results = await provider.search(
        '盛世春天',
        proximity: shijiazhuang,
        language: 'zh',
      );
      expect(results.first.address, contains('石家庄'));
      expect(results.first.reference?.provider, 'amap');
      expect(
        const ProviderPolicy(MapProvider.independent)
            .canDisplay(results.first.reference),
        isTrue,
      );
      final further = await provider.searchFurther(
        '盛世春天 test',
        proximity: shijiazhuang,
        language: 'zh',
      );
      expect(further, hasLength(2));
      expect(hosts.every((host) => !host.contains('photon')), isTrue);
      provider.dispose();
    });

    test('a Worker failure is reported instead of falling to Photon', () async {
      final hosts = <String>[];
      final provider = IndependentSearchProvider(
        requestSpacing: Duration.zero,
        useWorkerSuggestions: true,
        client: MockClient((request) async {
          hosts.add(request.url.host);
          return http.Response('{"error":"down"}', 503);
        }),
      );
      await expectLater(
        provider.search('盛世春天', proximity: shijiazhuang, language: 'zh'),
        throwsStateError,
      );
      expect(hosts.any((host) => host.contains('photon')), isFalse);
      provider.dispose();
    });

    test('long-press labels come from the Worker (Amap regeo)', () async {
      final provider = IndependentSearchProvider(
        requestSpacing: Duration.zero,
        client: MockClient((request) async {
          expect(request.url.path, '/api/reverse');
          return http.Response(
            jsonEncode({
              'label': '石家庄市长安区建设北大街56号',
              'countryCode': 'CN',
              'provider': 'amap',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final place = await provider.reverseNear(
        const GeoPoint(38.0409, 114.5163),
        language: 'zh',
      );
      expect(place?.address, '石家庄市长安区建设北大街56号');
      expect(place?.reference?.provider, 'amap');
      provider.dispose();
    });
  });

  group('routing in mainland China', () {
    final plan = jsonDecode(
      File('test/support/amap_route_options.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    test('Amap routes parse into the existing route model', () {
      final route = RouteOption.fromJson(
        (plan['options'] as List).first as Map<String, dynamic>,
      );
      expect(route.provider, 'independent');
      expect(route.usesAmap, isTrue);
      expect(route.points.length, 8);
      expect(route.steps.map((step) => step.maneuverType), [
        'depart',
        'turn',
        'arrive',
        'depart',
        'turn',
        'arrive',
      ]);
      expect(route.steps[1].maneuverModifier, 'left');
      expect(route.steps[4].alongRouteMeters, 6166);
      expect(routeStepInstruction(route.steps[1], 'zh'), '左转，进入建设北大街');
      expect(route.trafficIntervals.length, 6);
      expect(route.hasTrafficData, isTrue);
      expect(route.conditions!.trafficLabel(true), '部分路段拥堵');
      expect(route.hasHeavyTraffic, isTrue);
    });

    test(
      'never calls public OSRM directly, even without the proxy flag',
      () async {
        final requested = <Uri>[];
        final provider = IndependentRoutingProvider(
          client: MockClient((request) async {
            requested.add(request.url);
            return http.Response(
              jsonEncode(plan),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        final result = await provider.route(
          origin: const GeoPoint(38.03, 114.5),
          destination: const GeoPoint(38.07, 114.56),
          stops: const [GeoPoint(38.05, 114.517)],
          language: 'zh',
          mode: WaybiTravelMode.drive,
        );
        expect(requested.single.path, '/api/route-options');
        expect(requested.single.queryParameters['provider'], 'independent');
        expect(result.options.single.usesAmap, isTrue);
        expect(result.options.single.waypoints, hasLength(3));
        provider.dispose();
      },
    );
  });

  group('search and route surfaces', () {
    testWidgets('full search warns about a distant only match', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FullScreenSearch(
            provider: _ListSearch([
              candidate(
                '盛世春天',
                const GeoPoint(33.5815, 114.0166),
                provider: 'osm',
              ),
            ]),
            resolve: (candidate) async =>
                candidate.toPlace(candidate.location!),
            language: 'zh',
            recent: const [],
            currentLocation: shijiazhuang,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '盛世春天');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.text('最近的匹配在 498 公里外'), findsOneWidget);
      expect(
        find.text('498 公里'),
        findsOneWidget,
        reason: 'distance on the row',
      );
      expect(find.byKey(const Key('amapAttribution')), findsNothing);
    });

    testWidgets('a nearby Amap match shows its attribution and no warning', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FullScreenSearch(
            provider: _ListSearch([
              candidate('盛世春天', const GeoPoint(38.0602, 114.5206)),
            ]),
            resolve: (candidate) async =>
                candidate.toPlace(candidate.location!),
            language: 'en',
            recent: const [],
            currentLocation: shijiazhuang,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '盛世春天');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.byKey(const Key('farMatchNotice')), findsNothing);
      expect(find.text('Places: $amapAttribution'), findsOneWidget);
      expect(find.byTooltip('Data credits'), findsOneWidget);
    });

    testWidgets('Enter on a distant first suggestion opens full search', (
      tester,
    ) async {
      final searched = <String>[];
      final selected = <PlaceCandidate>[];
      var results = [
        candidate('盛世春天', const GeoPoint(33.5815, 114.0166), provider: 'osm'),
      ];
      await tester.pumpWidget(
        _app(
          CompanionSearchPrompt(
            marker: LocationMarkerStyle.kiwi,
            language: 'zh',
            currentLocation: shijiazhuang,
            loadSuggestions: (_) async => results,
            onSuggestionSelected: selected.add,
            onSearch: searched.add,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('companionSearchInput')),
        '盛世春天',
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(find.text('最近的匹配在 498 公里外'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(searched, ['盛世春天']);
      expect(selected, isEmpty);

      results = [candidate('盛世春天', const GeoPoint(38.0602, 114.5206))];
      await tester.enterText(
        find.byKey(const Key('companionSearchInput')),
        '盛世春天 ',
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(find.byKey(const Key('farMatchNotice')), findsNothing);
      expect(find.byKey(const Key('amapAttribution')), findsOneWidget);
      await tester.tap(find.byKey(const Key('companionSearchSubmit')));
      await tester.pump();
      expect(selected.single.name, '盛世春天');
    });

    testWidgets('route preview cautions a far destination and credits Amap', (
      tester,
    ) async {
      final route = RouteOption.fromJson(
        (jsonDecode(
              File('test/support/amap_route_options.json').readAsStringSync(),
            ) as Map<String, dynamic>)['options'][0]
            as Map<String, dynamic>,
      );
      final far = RouteOption(
        id: 'drive-far',
        mode: WaybiTravelMode.drive,
        durationSeconds: 20000,
        distanceMeters: 564000,
        points: const [shijiazhuang, GeoPoint(33.5815, 114.0166)],
        provider: 'independent',
        traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
        trafficIntervals: const [],
      );
      Widget sheet(RouteOption selected, {PlaceKind? kind}) => _app(
        SingleChildScrollView(
          child: RoutePreviewSheet(
            destinationTitle: '盛世春天',
            originTitle: '当前位置',
            plan: RoutePlan(
              options: [selected],
              trafficAvailable: true,
              provider: 'independent',
              stopsApplied: 0,
            ),
            selectedMode: WaybiTravelMode.drive,
            selectedRouteId: selected.id,
            busy: false,
            stopCount: 0,
            cameraCount: 0,
            customOrigin: false,
            onModeChanged: (_) {},
            onRouteSelected: (_) {},
            onStart: () {},
            onAddStop: () {},
            onSave: () {},
            isFavorite: false,
            onFavorite: () {},
            onReview: () {},
            onClose: () {},
            isChinese: true,
            destinationKind: kind,
          ),
        ),
      );
      await tester.pumpWidget(sheet(far));
      expect(find.text('该地点在 498 公里外'), findsOneWidget);
      expect(find.byKey(const Key('amapAttribution')), findsNothing);
      await tester.pumpWidget(sheet(far, kind: PlaceKind.coordinate));
      expect(find.byKey(const Key('farMatchNotice')), findsNothing);
      await tester.pumpWidget(sheet(route));
      expect(find.byKey(const Key('farMatchNotice')), findsNothing);
      expect(find.text('路线与路况：$amapAttribution'), findsOneWidget);
    });

    testWidgets('the place card cautions a distant named place', (
      tester,
    ) async {
      Widget card(PlaceSummary place, RouteOption route) => _app(
        PlaceDetailsContent(
          selectedPlace: place,
          details: null,
          detailsLoading: false,
          detailsError: null,
          routeBusy: false,
          quickRoute: route,
          isFavorite: false,
          onClose: () {},
          onNavigate: () {},
          onFavorite: () {},
          onReview: () {},
          language: 'en',
        ),
      );
      const luohe = GeoPoint(33.5815, 114.0166);
      final far = RouteOption(
        id: 'drive-0',
        mode: WaybiTravelMode.drive,
        durationSeconds: 20000,
        distanceMeters: 564000,
        points: const [shijiazhuang, luohe],
        provider: 'independent',
        routingEngine: 'amap',
        traffic: const TrafficSummary(normal: 1, slow: 0, trafficJam: 1),
        trafficIntervals: const [
          TrafficInterval(
            startPolylinePointIndex: 0,
            endPolylinePointIndex: 1,
            speed: 'trafficJam',
          ),
        ],
      );
      await tester.pumpWidget(
        card(const PlaceSummary(name: '盛世春天', location: luohe), far),
      );
      expect(find.text('This place is 498 km away'), findsOneWidget);
      expect(find.text('Route & traffic: $amapAttribution'), findsOneWidget);
      expect(find.text('Heavy sections'), findsOneWidget);

      final slow = RouteOption(
        id: 'drive-1',
        mode: WaybiTravelMode.drive,
        durationSeconds: 600,
        distanceMeters: 3000,
        points: const [shijiazhuang, GeoPoint(38.06, 114.52)],
        provider: 'independent',
        traffic: const TrafficSummary(normal: 1, slow: 1, trafficJam: 0),
        trafficIntervals: const [
          TrafficInterval(
            startPolylinePointIndex: 0,
            endPolylinePointIndex: 1,
            speed: 'slow',
          ),
        ],
      );
      await tester.pumpWidget(
        card(
          const PlaceSummary(name: '盛世春天', location: GeoPoint(38.06, 114.52)),
          slow,
        ),
      );
      expect(find.byKey(const Key('farMatchNotice')), findsNothing);
      expect(find.byKey(const Key('amapAttribution')), findsNothing);
      expect(find.text('Slow sections'), findsOneWidget);
    });

    testWidgets('data credits name AutoNavi for Amap results', (tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showPlaceSources(
                context,
                language: 'zh',
                providerIds: const ['amap', 'osm'],
              ),
              child: const Text('credits'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('credits'));
      await tester.pumpAndSettle();
      expect(find.text('© $amapAttribution'), findsOneWidget);
      expect(find.textContaining('中国大陆的地点、路线与路况由高德地图提供'), findsOneWidget);
    });

    testWidgets('the caution meets the touch-target height and reads aloud', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          const FarMatchNotice(
            title: 'Nearest match is 494 km away',
            detail: 'Check',
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(const Key('farMatchNotice'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        find.bySemanticsLabel('Nearest match is 494 km away. Check'),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });
}
