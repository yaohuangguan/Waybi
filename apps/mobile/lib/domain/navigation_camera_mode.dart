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
