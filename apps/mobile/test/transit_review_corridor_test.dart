import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/transit_lane_map.dart';
import 'package:waybi_mobile/domain/transit_review_corridor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the five council corridors load offline as review-only geometry',
    () async {
      final rows = await loadBundledTransitReviewCorridors();
      expect(rows.length, 54);
      expect(rows.map((x) => x.city).toSet(), {'Christchurch', 'Wellington'});
      expect(rows.map((x) => x.roadName).toSet(), {
        'Cranford Street',
        'Papanui Road',
        'Adelaide Road',
        'Kent Terrace',
        'Cambridge Terrace',
      });
      expect(rows.every((x) => x.points.length >= 2), isTrue);
      expect(rows.every((x) => x.ruleSource.startsWith('https://')), isTrue);
    },
  );

  test('unverified council street centrelines can only render as amber review candidates', () async {
    final rows = await loadBundledTransitReviewCorridors();
    final features =
        transitLaneFeatureCollection(
              const [],
              DateTime.utc(2026, 10, 9),
              rows,
            )['features']
            as List;
    expect(features.length, 54);
    expect(
      features.every((x) => (x['id'] as String).startsWith('review:')),
      isTrue,
    );
    expect(
      features.every(
        (x) => (x['properties'] as Map)['laneStatus'] == 'candidate',
      ),
      isTrue,
    );
    expect(
      features.any((x) => (x['properties'] as Map)['laneStatus'] == 'active'),
      isFalse,
    );
  });

  test('rejects candidate geometry when precision or verified source provenance is missing', () {
    final base = {
      'id': 'demo',
      'city': 'Christchurch',
      'roadName': 'Test',
      'authority': 'Christchurch City Council',
      'ruleSummary': 'Check signs',
      'ruleSummaryZh': '请查看路牌',
      'ruleSource': 'https://ccc.govt.nz/',
      'geometrySource': 'https://gis.ccc.govt.nz/',
      'precision': 'corridor-only',
      'coordinates': [
        [172.6, -43.5],
        [172.61, -43.51],
      ],
    };
    expect(
      () => TransitReviewCorridor.fromJson({...base, 'precision': 'surveyed'}),
      throwsFormatException,
    );
    expect(
      () => TransitReviewCorridor.fromJson({
        ...base,
        'ruleSource': 'http://example.com',
      }),
      throwsFormatException,
    );
    expect(
      () => TransitReviewCorridor.fromJson({
        ...base,
        'coordinates': [
          [172.6, -43.5],
        ],
      }),
      throwsFormatException,
    );
  });
}
