import 'package:test/test.dart';
import 'package:waybi_map/waybi_map.dart';

void main() {
  test('route paths compare geometry by revision or list identity', () {
    const points = [GeoPoint(-36.85, 174.76), GeoPoint(-36.86, 174.77)];
    const a = MapRoutePath(id: 'r', points: points, revision: 1);
    expect(
      a.sameGeometry(const MapRoutePath(id: 'r', points: [], revision: 1)),
      isTrue,
    );
    expect(
      a.sameGeometry(const MapRoutePath(id: 'r', points: points, revision: 2)),
      isFalse,
    );
    expect(
      a.sameGeometry(const MapRoutePath(id: 'x', points: points, revision: 1)),
      isFalse,
    );
    const plain = MapRoutePath(
      id: 'r',
      points: points,
      progressMeters: 10,
      live: true,
    );
    expect(
      plain.sameGeometry(const MapRoutePath(id: 'r', points: points)),
      isTrue,
    );
    expect(plain.sameGeometry(a), isFalse);
    expect(plain.progressMeters, 10);
    expect(plain.live, isTrue);
  });
}
