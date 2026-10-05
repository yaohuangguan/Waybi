enum NavigationCameraMode {
  headingUpFlat,
  headingUpPerspective,
  northUpFlat;

  bool get northUp => this == NavigationCameraMode.northUpFlat;

  bool get tilted => this == NavigationCameraMode.headingUpPerspective;

  NavigationCameraMode get next => switch (this) {
    NavigationCameraMode.headingUpFlat =>
      NavigationCameraMode.headingUpPerspective,
    NavigationCameraMode.headingUpPerspective =>
      NavigationCameraMode.northUpFlat,
    NavigationCameraMode.northUpFlat => NavigationCameraMode.headingUpFlat,
  };
}

double navigationForwardBearing({
  required double speedKph,
  double? course,
  double? compass,
  double? routeBearing,
}) {
  final moving = speedKph.isFinite && speedKph >= 3;
  final candidates = moving
      ? [course, compass, routeBearing]
      : [compass, course, routeBearing];
  for (final value in candidates) {
    if (value != null && value.isFinite) return (value % 360 + 360) % 360;
  }
  return 0;
}
