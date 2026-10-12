/// Road direction constraints are valid only for an accurate, recent moving fix.
/// Stationary compasses and manually selected origins must remain unconstrained.
double? routingOriginHeading({
  required double? heading,
  required double speedMetresPerSecond,
  required double accuracyMeters,
  required DateTime timestamp,
  required DateTime now,
  bool manualOrigin = false,
}) {
  if (manualOrigin ||
      heading == null ||
      !heading.isFinite ||
      !speedMetresPerSecond.isFinite ||
      speedMetresPerSecond < 2.8 ||
      !accuracyMeters.isFinite ||
      accuracyMeters < 0 ||
      accuracyMeters > 25 ||
      now.difference(timestamp).abs() > const Duration(seconds: 10)) {
    return null;
  }
  return (heading % 360 + 360) % 360;
}
