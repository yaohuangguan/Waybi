import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/navigation_camera_mode.dart';

void main() {
  test(
    'stationary navigation uses phone direction, moving navigation uses course',
    () {
      expect(
        navigationForwardBearing(speedKph: 0, compass: 92, course: 180),
        92,
      );
      expect(
        navigationForwardBearing(speedKph: 60, compass: 92, course: 180),
        180,
      );
      expect(
        navigationForwardBearing(speedKph: 0, compass: double.nan, course: 270),
        270,
      );
      expect(navigationForwardBearing(speedKph: 40, routeBearing: -10), 350);
      expect(navigationForwardBearing(speedKph: 0), 0);
    },
  );
}
