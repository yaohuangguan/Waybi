import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/data/place_details_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/widgets/place_details_content.dart';

class PictureClient implements HttpClient {
  PictureClient(this.bytes);
  final Uint8List bytes;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      PictureRequest(bytes, url.path.contains('missing') ? 404 : 200);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class PictureRequest implements HttpClientRequest {
  PictureRequest(this.bytes, this.status);
  final Uint8List bytes;
  final int status;
  @override
  HttpHeaders get headers => PictureHeaders();
  @override
  Future<HttpClientResponse> close() async => PictureResponse(bytes, status);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class PictureHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class PictureResponse extends Stream<List<int>> implements HttpClientResponse {
  PictureResponse(this.bytes, this.statusCode);
  final Uint8List bytes;
  @override
  final int statusCode;
  @override
  int get contentLength => statusCode == 200 ? bytes.length : 0;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  Stream<List<int>> chunks() async* {
    if (statusCode != 200) return;
    final middle = bytes.length ~/ 2;
    yield bytes.sublist(0, middle);
    await Future<void>.delayed(const Duration(milliseconds: 12));
    yield bytes.sublist(middle);
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => chunks().listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const chosen = PlaceSummary(
  name: 'Harbour café',
  address: '1 Long Harbour Road, Auckland',
  location: GeoPoint(-36.85, 174.76),
  reference: ProviderReference('osm', 'node:1'),
  category: 'cafe',
);
PlaceDetails rich({
  bool photos = true,
  bool brokenAvatar = false,
  String status = 'OPERATIONAL',
}) => PlaceDetails(
  placeId: 'node:1',
  name: 'Harbour café',
  address: '1 Long Harbour Road, Auckland',
  primaryType: 'cafe',
  rating: 4.8,
  userRatingCount: 321,
  businessStatus: status,
  priceLevel: 'PRICE_LEVEL_MODERATE',
  phone: '09 000 0000',
  websiteUri: 'https://example.test/cafe',
  googleMapsUri: '',
  editorialSummary: 'A quiet place beside the harbour.',
  openingHours: ['Monday 08:00–17:00', 'Tuesday 08:00–17:00'],
  photos: photos
      ? [
          const PlacePhoto(
            name: '',
            attribution: 'Image A',
            directUrl: 'https://images.example.test/a.png',
            sourceUrl: 'https://example.test/source-a',
          ),
          const PlacePhoto(
            name: '',
            attribution: 'Image B',
            directUrl: 'https://images.example.test/missing.png',
            licenseUrl: 'https://example.test/licence-b',
          ),
          const PlacePhoto(
            name: '',
            attribution: 'Unsafe source',
            directUrl: 'https://images.example.test/c.png',
            sourceUrl: 'http://example.test/unsafe',
          ),
        ]
      : [],
  reviews: [
    PlaceReview(
      author: 'Harbour visitor',
      authorPhoto: brokenAvatar
          ? 'https://images.example.test/missing-avatar.png'
          : 'https://images.example.test/visitor.png',
      rating: 4.5,
      text: 'Easy access and a clear entrance.',
      relativeTime: '1 day ago',
      googleMapsUri: null,
    ),
  ],
);
RouteOption driveRoute(int seconds, {int distance = 800, int? delay}) =>
    RouteOption(
      id: 'preview',
      mode: WaybiTravelMode.drive,
      durationSeconds: seconds,
      distanceMeters: distance,
      provider: 'independent',
      traffic: const TrafficSummary(normal: 1, slow: 0, trafficJam: 0),
      trafficIntervals: const [],
      trafficDelaySeconds: delay,
      points: const [GeoPoint(-36.85, 174.76), GeoPoint(-36.86, 174.77)],
    );
Future<void> frames(WidgetTester t, [int count = 16]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 30));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(t.takeException(), isNull);
}

Future<void> card(
  WidgetTester t, {
  String language = 'en',
  PlaceSummary selected = chosen,
  PlaceDetails? details,
  RouteOption? route,
  bool busy = false,
  bool available = true,
  bool loading = false,
  String? error,
  bool saved = false,
  ValueChanged<bool>? expanded,
  VoidCallback? navigate,
  VoidCallback? favorite,
  VoidCallback? review,
  VoidCallback? close,
}) async {
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: PlaceDetailsContent(
            key: const ValueKey('place-card'),
            selectedPlace: selected,
            details: details,
            detailsLoading: loading,
            detailsError: error,
            routeBusy: busy,
            quickRoute: route,
            isFavorite: saved,
            navigationAvailable: available,
            language: language,
            onExpandedChanged: expanded,
            onNavigate: navigate ?? () {},
            onFavorite: favorite ?? () {},
            onReview: review ?? () {},
            onClose: close ?? () {},
          ),
        ),
      ),
    ),
  );
  await frames(t);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List bytes;
  String copied = '';
  final launched = <String>[];
  setUpAll(() {
    bytes = File('assets/icon/app_icon.png').readAsBytesSync();
  });
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    copied = '';
    launched.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      if (call.method == 'Clipboard.getData') return {'text': copied};
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
          return true;
        }
        if (call.method == 'canLaunch') return true;
        return null;
      },
    );
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      null,
    );
  });
  void pictureTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      await HttpOverrides.runZoned(() async {
        await body(t);
        await t.pumpWidget(const SizedBox.shrink());
        await frames(t, 3);
      }, createHttpClient: (_) => PictureClient(bytes));
    });
  }

  for (final language in ['en', 'zh']) {
    pictureTest(
      'rich $language place details share, show hours, page credited images and keep actions connected',
      (t) async {
        var navigate = 0, favorite = 0, review = 0;
        await card(
          t,
          language: language,
          details: rich(),
          route: driveRoute(7260, delay: 180),
          navigate: () => navigate++,
          favorite: () => favorite++,
          review: () => review++,
        );
        await t.tap(find.text(language == 'zh' ? '分享' : 'Share'));
        await frames(t);
        expect(copied, contains('Harbour café'));
        expect(copied, contains('-36.85,174.76'));
        ScaffoldMessenger.of(t.element(find.byType(PlaceDetailsContent)))
            .removeCurrentSnackBar();
        await frames(t);
        await t.tap(find.text(language == 'zh' ? '导航' : 'Drive'));
        await t.tap(find.byIcon(Icons.favorite_border_rounded));
        await t.tap(find.byIcon(Icons.more_horiz_rounded));
        expect([navigate, favorite, review], [1, 1, 1]);
        await t.tap(find.byKey(const Key('placeDeckHandle')));
        await frames(t);
        expect(find.text('© Image A'), findsOneWidget);
        await t.tap(find.text('© Image A'));
        await frames(t);
        expect(launched, contains('https://example.test/source-a'));
        await t.drag(find.byType(PageView), const Offset(-430, 0));
        await frames(t);
        expect(find.byIcon(Icons.image_not_supported_outlined), findsWidgets);
        await t.tap(find.text('© Image B'));
        await frames(t);
        expect(launched, contains('https://example.test/licence-b'));
        await t.drag(find.byType(PageView), const Offset(-430, 0));
        await frames(t);
        final count = launched.length;
        await t.tap(find.text('© Unsafe source'));
        await frames(t);
        expect(launched, hasLength(count));
        final hours = find.text(language == 'zh' ? '营业时间' : 'Opening hours');
        await t.ensureVisible(hours);
        await t.tap(hours);
        await frames(t);
        expect(find.text('Monday 08:00–17:00'), findsOneWidget);
        expect(find.text('Harbour visitor'), findsOneWidget);
        expect(find.text('4.5 ★'), findsOneWidget);
      },
    );
  }
  pictureTest(
    'a missing review avatar falls back to the person icon without a frame error',
    (t) async {
      await card(t, details: rich(photos: false, brokenAvatar: true));
      await t.tap(find.byKey(const Key('placeDeckHandle')));
      await frames(t);
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    },
  );
  pictureTest(
    'a closed place keeps details and the same provider reference preserves expansion',
    (t) async {
      final expanded = <bool>[];
      await card(
        t,
        details: rich(photos: false, status: 'CLOSED_TEMPORARILY'),
        expanded: expanded.add,
      );
      expect(find.text('CLOSED TEMPORARILY'), findsOneWidget);
      await t.drag(
        find.byKey(const Key('placeDeckHandle')),
        const Offset(0, -70),
      );
      await frames(t);
      expect(expanded.last, isTrue);
      await card(
        t,
        selected: const PlaceSummary(
          name: 'Renamed café',
          location: GeoPoint(-36.85, 174.76),
          reference: ProviderReference('osm', 'node:1'),
        ),
        details: rich(photos: false),
      );
      expect(find.text('Opening hours'), findsOneWidget);
      await card(
        t,
        selected: const PlaceSummary(
          name: 'Different place',
          location: GeoPoint(-36.86, 174.77),
          reference: ProviderReference('osm', 'node:2'),
        ),
        details: rich(photos: false),
      );
      expect(find.text('Opening hours'), findsNothing);
    },
  );
  pictureTest(
    'routing busy and unavailable regions disable navigation while save and review stay usable',
    (t) async {
      var navigate = 0, favorite = 0, review = 0;
      await card(
        t,
        busy: true,
        loading: true,
        error: 'Details unavailable',
        saved: true,
        navigate: () => navigate++,
        favorite: () => favorite++,
        review: () => review++,
      );
      expect(find.text('Routing'), findsOneWidget);
      expect(find.text('Details unavailable'), findsOneWidget);
      await t.tap(find.text('Routing'));
      expect(navigate, 0);
      await card(
        t,
        available: false,
        navigate: () => navigate++,
        favorite: () => favorite++,
        review: () => review++,
      );
      expect(
        find.textContaining('Navigation is unavailable for this location.'),
        findsOneWidget,
      );
      await t.ensureVisible(find.text('No road route'));
      await t.tap(find.text('No road route'));
      await t.tap(find.text('Save'));
      await t.tap(find.text('More'));
      expect([navigate, favorite, review], [0, 1, 1]);
    },
  );
  pictureTest(
    'route duration formatting covers exact hours and sub-kilometre distances',
    (t) async {
      await card(t, route: driveRoute(7200), details: rich(photos: false));
      expect(find.text('2h'), findsOneWidget);
      expect(find.text('· 800 m'), findsOneWidget);
      await card(
        t,
        language: 'zh',
        route: driveRoute(7260, distance: 12500),
        details: rich(photos: false),
      );
      expect(find.text('2 小时 1 分'), findsOneWidget);
      expect(find.text('· 13 公里'), findsOneWidget);
    },
  );
  pictureTest(
    'coordinate places have a readable address and collapse when a different coordinate is selected',
    (t) async {
      var closed = 0;
      await card(
        t,
        selected: const PlaceSummary(
          name: 'Pin',
          location: GeoPoint(-36.85, 174.76),
        ),
        details: rich(photos: false),
        close: () => closed++,
      );
      await t.drag(
        find.byKey(const Key('placeDeckHandle')),
        const Offset(0, -60),
      );
      await frames(t);
      await t.drag(
        find.byKey(const Key('placeDeckHandle')),
        const Offset(0, 70),
      );
      await frames(t);
      expect(find.text('Opening hours'), findsNothing);
      await card(
        t,
        selected: const PlaceSummary(
          name: 'New pin',
          location: GeoPoint(-36.86, 174.77),
        ),
        close: () => closed++,
      );
      expect(find.byKey(const Key('placeFullAddress')), findsOneWidget);
      await t.tap(find.byTooltip('Close'));
      expect(closed, 1);
    },
  );
}
