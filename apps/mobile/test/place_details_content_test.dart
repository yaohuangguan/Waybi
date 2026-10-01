import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_lens_mobile/data/place_details_repository.dart';
import 'package:kiwi_lens_mobile/domain/map_provider.dart';
import 'package:kiwi_lens_mobile/widgets/place_details_content.dart';

void main() {
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
              isFavorite: false,
              onClose: () {},
              onNavigate: () {},
              onFavorite: () {},
              onReview: () {},
              language: 'zh',
            ),
          ),
        ),
      ),
    );

    expect(find.text('导航'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('分享'), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);
    expect(find.text('上拉查看更多'), findsOneWidget);
    expect(find.text('营业时间'), findsNothing);

    await tester.tap(find.byKey(const Key('placeDeckHandle')));
    await tester.pumpAndSettle();

    expect(find.text('营业时间'), findsOneWidget);
    expect(find.text('Google 评价'), findsOneWidget);
    expect(find.text('显示 1 条'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
