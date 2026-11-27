import 'package:flutter/widgets.dart';

/// Whether the vehicle is moving, for widgets that must not ask for
/// fine-grained input while driving (parking choice, trip tools).
///
/// The navigation overlay provides it from GPS speed with hysteresis, so a
/// stop at lights does not flicker the UI.
class DrivingMotion extends InheritedWidget {
  const DrivingMotion({super.key, required this.moving, required super.child});

  final bool moving;

  /// Starts counting as moving at this speed…
  static const movingKph = 8.0;

  /// …and as stopped again below this one.
  static const stoppedKph = 4.0;

  /// The next motion state for [speedKph] given the [previous] state.
  static bool next(bool previous, double speedKph) =>
      previous ? speedKph >= stoppedKph : speedKph >= movingKph;

  /// The nearest motion state, or false when no navigation surface provides
  /// one.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DrivingMotion>()?.moving ??
      false;

  @override
  bool updateShouldNotify(DrivingMotion oldWidget) =>
      oldWidget.moving != moving;
}
