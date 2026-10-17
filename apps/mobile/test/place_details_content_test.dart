import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/data/place_details_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/widgets/place_details_content.dart';

void main() {
  testWidgets(
    'cross-sea destination remains browseable but never spins or starts driving',
    (tester) async {
      var navigationAttempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaceDetailsContent(
              selectedPlace: const PlaceSummary(
                name: 'Sydney Opera House',
                location: GeoPoint(-33.8568, 151.2153),
                address: 'Sydney NSW',
                category: 'attraction',
              ),
              details: null,
              detailsLoading: false,
              detailsError: null,
              routeBusy: false,
              navigationAvailable: false,
              navigationUnavailableReason: '新西兰和澳大利亚之间无法直接驾车抵达。',
              quickRouteLoading: false,
              isFavorite: false,
              onClose: () {},
              onNavigate: () => navigationAttempts++,
              onFavorite: () {},
              onReview: () {},
              language: 'zh',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('无法直接驾车抵达'), findsOneWidget);
      expect(find.text('无法驾车抵达'), findsOneWidget);
      expect(find.text('仅新西兰'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Sydney Opera House'), findsWidgets);
      expect(navigationAttempts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed quick route ends spinner with actionable failure message',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaceDetailsContent(
              selectedPlace: const PlaceSummary(
                name: 'Melbourne',
                location: GeoPoint(-37.8136, 144.9631),
                address: 'Melbourne VIC',
                category: 'city',
              ),
              details: null,
              detailsLoading: false,
              detailsError: null,
              routeBusy: false,
              quickRouteIssue: '路线服务暂时不可用，请稍后重试。',
              quickRouteLoading: false,
              isFavorite: false,
              onClose: () {},
              onNavigate: () {},
              onFavorite: () {},
              onReview: () {},
              language: 'zh',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('路线服务暂时不可用'), findsOneWidget);
      expect(find.text('正在获取驾车时间…'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('place deck starts compact and expands for details in Chinese', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const selected = PlaceSummary(
      name: 'Auckland Art Gallery',
      location: GeoPoint(-36.8514, 174.7663),
      address: 'Wellesley Street East',
      category: 'art gallery',
    );
    const quickRoute = RouteOption(
      id: 'drive-fast',
      mode: WaybiTravelMode.drive,
      durationSeconds: 720,
      staticDurationSeconds: 480,
      trafficDelaySeconds: 240,
      distanceMeters: 8400,
      points: [GeoPoint(-36.8514, 174.7663), GeoPoint(-36.86, 174.78)],
      provider: 'google',
      traffic: TrafficSummary(normal: 10, slow: 3, trafficJam: 0),
      trafficIntervals: [],
    );
    const details = PlaceDetails(
      placeId: 'gallery',
      name: 'Auckland Art Gallery',
      address: 'Wellesley Street East',
      primaryType: 'art_gallery',
      rating: 4.7,
      userRatingCount: 3210,
      businessStatus: 'OPERATIONAL',
      priceLevel: null,
      phone: '09 000 0000',
      websiteUri: '',
      googleMapsUri: '',
      editorialSummary: 'A city-centre gallery.',
      openingHours: ['星期四：10:00–17:00'],
      photos: [],
      reviews: [
        PlaceReview(
          author: 'Sam',
          authorPhoto: null,
          rating: 5,
          text: '很好',
          relativeTime: '1 天前',
          googleMapsUri: null,
        ),
      ],
    );

    bool? expanded;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PlaceDetailsContent(
              selectedPlace: selected,
              details: details,
              detailsLoading: false,
              detailsError: null,
              routeBusy: false,
              quickRoute: quickRoute,
              isFavorite: false,
              onClose: () {},
              onNavigate: () {},
              onFavorite: () {},
              onReview: () {},
              language: 'zh',
              onExpandedChanged: (value) => expanded = value,
            ),
          ),
        ),
      ),
    );

    expect(find.text('导航'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('分享'), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);
    expect(find.text('12 分钟'), findsOneWidget);
    expect(find.text('· 8.4 公里'), findsOneWidget);
    expect(find.text('拥堵 +4 分钟'), findsOneWidget);
    expect(find.text('上拉查看更多'), findsOneWidget);
    expect(find.text('营业时间'), findsNothing);

    await tester.tap(find.byKey(const Key('placeDeckHandle')));
    await tester.pumpAndSettle();

    expect(expanded, isTrue);
    expect(find.text('营业时间'), findsOneWidget);
    expect(find.text('Google 评价'), findsOneWidget);
    expect(find.text('显示 1 条'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
