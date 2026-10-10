import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/drive/independent_navigation_camera.dart';

void main() {
  const point = GeoPoint(-36.8485, 174.7633);
  const turn = RouteStepInfo(
    instruction: 'Turn right',
    distanceMeters: 200,
    location: point,
    maneuverType: 'turn',
    maneuverModifier: 'right',
  );
  MapViewportState frame(
    IndependentNavigationCamera camera, {
    GeoPoint location = point,
    double speed = 50,
    double distance = 1000,
    RouteStepInfo? step = turn,
    int seconds = 0,
    double heading = 0,
    bool north = false,
    bool offRoute = false,
    WaybiTravelMode mode = WaybiTravelMode.drive,
  }) => camera.update(
    location: location,
    heading: heading,
    speedKph: speed,
    mode: mode,
    visibleHeight: 500,
    distanceToStep: distance,
    nextStep: step,
    northUp: north,
    tilted: false,
    now: DateTime(2026).add(Duration(seconds: seconds)),
    offRoute: offRoute,
  );

  test('city and motorway framing show useful road distances', () {
    final city = frame(IndependentNavigationCamera());
    final highway = frame(IndependentNavigationCamera(), speed: 100);
    expect(city.zoom, inInclusiveRange(16.0, 16.7));
    expect(highway.zoom, inInclusiveRange(15.5, 16.2));
    expect(highway.zoom, lessThan(city.zoom));
  });
  test(
    'moving trajectory follows every location and turns across north smoothly',
    () {
      final camera = IndependentNavigationCamera();
      frame(camera, heading: 355);
      const moved = GeoPoint(-36.848, 174.7634);
      final next = frame(camera, location: moved, heading: 5, seconds: 1);
      expect(next.center, moved);
      expect(next.bearing, closeTo(5, .001));
    },
  );
  test('approaching junction zooms in continuously then widens slowly', () {
    final camera = IndependentNavigationCamera();
    final far = frame(camera);
    final approaching = frame(camera, distance: 180, seconds: 1);
    final near = frame(camera, distance: 30, seconds: 2);
    final close = frame(camera, distance: 15, seconds: 3);
    final after = frame(camera, distance: 1000, seconds: 4);
    expect(approaching.zoom, greaterThan(far.zoom));
    expect(near.zoom, greaterThan(approaching.zoom));
    expect(close.zoom, inInclusiveRange(18.0, 18.2));
    expect(after.zoom, closeTo(close.zoom - .28, .001));
  });
  test(
    'straight instructions and stale off-route maneuvers do not zoom in',
    () {
      const straight = RouteStepInfo(
        instruction: 'Continue',
        distanceMeters: 200,
        location: point,
        maneuverType: 'continue',
        maneuverModifier: 'straight',
      );
      final base = frame(IndependentNavigationCamera());
      expect(
        frame(IndependentNavigationCamera(), step: straight, distance: 5).zoom,
        base.zoom,
      );
      expect(
        frame(IndependentNavigationCamera(), distance: 5, offRoute: true).zoom,
        base.zoom,
      );
      expect(
        frame(IndependentNavigationCamera(), step: null, distance: 0).zoom,
        base.zoom,
      );
      expect(
        frame(IndependentNavigationCamera(), distance: -20).zoom,
        base.zoom,
      );
      expect(
        frame(IndependentNavigationCamera(), distance: double.nan).zoom,
        base.zoom,
      );
    },
  );
  test(
    'last city blocks are legible before the turn, with more motorway context',
    () {
      final hundred = frame(
        IndependentNavigationCamera(),
        speed: 30,
        distance: 100,
      );
      final fifty = frame(
        IndependentNavigationCamera(),
        speed: 30,
        distance: 50,
      );
      final twenty = frame(
        IndependentNavigationCamera(),
        speed: 30,
        distance: 20,
      );
      final motorway = frame(
        IndependentNavigationCamera(),
        speed: 100,
        distance: 20,
      );
      expect(hundred.zoom, greaterThan(17));
      expect(fifty.zoom, greaterThan(17.8));
      expect(twenty.zoom, inInclusiveRange(18.1, 18.2));
      expect(motorway.zoom, lessThan(twenty.zoom));
    },
  );
  test('recenter resets overview framing and north-up remains north', () {
    final camera = IndependentNavigationCamera();
    frame(camera, distance: 0);
    camera.reset();
    final next = frame(camera, heading: 150, north: true);
    expect(next.bearing, 0);
    expect(next.zoom, frame(IndependentNavigationCamera()).zoom);
    expect(
      frame(IndependentNavigationCamera(), mode: WaybiTravelMode.walk).zoom,
      greaterThan(next.zoom),
    );
  });
}
