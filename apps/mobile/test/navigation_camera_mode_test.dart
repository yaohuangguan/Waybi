import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_lens_mobile/domain/navigation_camera_mode.dart';

void main() {
  test('camera mode cycles heading flat, perspective, north up, then flat', () {
    var mode = NavigationCameraMode.headingUpFlat;
    expect(mode.northUp, isFalse);
    expect(mode.tilted, isFalse);

    mode = mode.next;
    expect(mode, NavigationCameraMode.headingUpPerspective);
    expect(mode.tilted, isTrue);

    mode = mode.next;
    expect(mode, NavigationCameraMode.northUpFlat);
    expect(mode.northUp, isTrue);
    expect(mode.tilted, isFalse);

    mode = mode.next;
    expect(mode, NavigationCameraMode.headingUpFlat);
  });
}
