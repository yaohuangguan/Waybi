import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/navigation_link.dart';
import 'package:waybi_mobile/domain/route_option.dart';

void main() {
  test('calendar address is decoded once and kept for user selection', () {
    final link = NavigationLink.parse(
      'waybi://navigate?destination=Westfield%20Newmarket%2C%20Auckland',
    )!;
    expect(link.destination.label, 'Westfield Newmarket, Auckland');
    expect(link.destination.coordinate, isNull);
    expect(link.mode, WaybiTravelMode.drive);
  });

  test(
    'coordinates and Unicode place label are independent of provider IDs',
    () {
      final uri = Uri(
        scheme: 'waybi',
        host: 'navigate',
        queryParameters: {
          'destination': '-36.8697,174.7762',
          'name': '新市场',
          'mode': 'walk',
        },
      );
      final link = NavigationLink.parse(uri.toString())!;
      expect(link.destination.coordinate!.latitude, -36.8697);
      expect(link.destination.coordinate!.longitude, 174.7762);
      expect(link.destination.label, '新市场');
      expect(link.mode, WaybiTravelMode.walk);
    },
  );

  test(
    'system directions retain explicit origin and ordered repeated stops',
    () {
      final link = NavigationLink.parse(
        'geo-navigation:///directions?source=-36.8,174.7&destination=Airport&waypoint=Newmarket&waypoint=-36.9,174.8',
      )!;
      expect(link.source!.coordinate!.latitude, -36.8);
      expect(link.waypoints.map((target) => target.label), [
        'Newmarket',
        '-36.9,174.8',
      ]);
      expect(link.destination.label, 'Airport');
    },
  );

  test('system place URLs open a place rather than request navigation', () {
    expect(
      NavigationLink.parse('geo-navigation://place?address=Queen%20Street')!
          .showPlaceOnly,
      isTrue,
    );
    expect(
      NavigationLink.parse('geo-navigation:///place?coordinate=-36.8,174.7')!
          .destination
          .coordinate,
      isNotNull,
    );
  });

  test('unrelated schemes including OAuth are left alone', () {
    expect(
      NavigationLink.parse(
        'com.googleusercontent.apps.example:/oauthredirect?code=example',
      ),
      isNull,
    );
    expect(NavigationLink.parse('https://example.com/directions'), isNull);
  });

  test(
    'reject malformed, ambiguous, nonfinite and out-of-range destinations',
    () {
      for (final value in [
        'waybi://navigate',
        'waybi://navigate?destination=',
        'waybi://navigate?destination=91,174',
        'waybi://navigate?destination=1,-181',
        'waybi://navigate?destination=NaN,12',
        'waybi://navigate?destination=Infinity,12',
        'waybi://navigate?destination=A&destination=B',
        'waybi://navigate?destination=A&mode=teleport',
        'waybi://user@navigate?destination=A',
        'waybi://navigate:99?destination=A',
        'waybi://navigate/other?destination=A',
        'waybi://navigate?destination=A#other',
        'geo-navigation://place?coordinate=Queen%20Street',
        'geo-navigation://place?coordinate=1,2&address=Queen%20Street',
        'geo-navigation://place?address=A&source=B',
        'waybi://navigate?destination=A%00B',
      ]) {
        expect(
          () => NavigationLink.parse(value),
          throwsFormatException,
          reason: value,
        );
      }
    },
  );
}
