import 'package:test/test.dart';
import 'package:waybi_map/waybi_map.dart';

void main() {
  test('resolved place preserves its provider identity and avoids duplicate address prefixes', () {
    const point = GeoPoint(-36.85, 174.76);
    const reference = ProviderReference('waybi', 'cafe');
    final candidate = PlaceCandidate(
      name: 'Cafe',
      address: '  CAFE, Queen Street  ',
      kind: PlaceKind.poi,
      category: 'coffee',
      reference: reference,
    );
    final place = candidate.toPlace(point);
    expect(candidate.secondaryAddress, 'Queen Street');
    expect(place.name, 'Cafe');
    expect(place.address, 'Queen Street');
    expect(place.reference, reference);
    expect(place.location, point);
    expect(place.category, 'coffee');
    expect(placeSecondaryAddress('Cafe', 'Other Road'), 'Other Road');
    expect(placeSecondaryAddress('Cafe', ''), '');
  });
  test(
    'unknown renderer capabilities stay disabled until explicitly advertised',
    () {
      final baseline = MapRendererCapabilities();
      expect([
        baseline.pitch,
        baseline.bearing,
        baseline.liveTraffic,
        baseline.customLayers,
        baseline.featurePicking,
      ], everyElement(isFalse));
      final enhanced = MapRendererCapabilities(
        pitch: true,
        bearing: true,
        liveTraffic: true,
        customLayers: true,
        featurePicking: true,
      );
      expect([
        enhanced.pitch,
        enhanced.bearing,
        enhanced.liveTraffic,
        enhanced.customLayers,
        enhanced.featurePicking,
      ], everyElement(isTrue));
    },
  );
  test('route overlay distinguishes remaining, traversed and temporary drive-trail geometry', () {
    final points = [const GeoPoint(-37, 174), const GeoPoint(-37, 174.01)];
    final remaining = MapRoutePath(
      id: 'remaining',
      points: points,
      active: true,
    );
    final traversed = MapRoutePath(
      id: 'passed',
      points: points,
      traversed: true,
    );
    final trail = MapRoutePath(id: 'drive', points: points, trail: true);
    expect(remaining.active, isTrue);
    expect(remaining.traversed, isFalse);
    expect(traversed.traversed, isTrue);
    expect(trail.trail, isTrue);
    expect(trail.points, points);
  });
}
