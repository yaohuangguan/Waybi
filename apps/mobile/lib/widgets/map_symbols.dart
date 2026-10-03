import '../theme/waybi_theme.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';

import '../domain/map_layer_settings.dart';
import '../domain/map_provider.dart';
import '../providers/camera_marker_art.dart';
import '../providers/destination_marker_art.dart';
import '../providers/location_marker_art.dart';

class MapSymbols {
  static final Map<CameraKind, ImageDescriptor> _normal = {};
  static final Map<CameraKind, ImageDescriptor> _route = {};
  static ImageDescriptor? car;
  static ImageDescriptor? finish;
  static ImageDescriptor? roadReport;
  static final Map<LocationMarkerStyle, ImageDescriptor> _location = {};
  static Future<void>? _registration;

  static ImageDescriptor? camera(CameraKind kind, {required bool onRoute}) =>
      (onRoute ? _route : _normal)[kind];

  static ImageDescriptor? location(LocationMarkerStyle style) =>
      _location[style];

  static Future<void> ensureRegistered() =>
      _registration ??= _registerAll().catchError((Object error) {
        _registration = null;
        throw error;
      });

  static Future<void> _registerAll() async {
    for (final kind in CameraKind.values) {
      _normal[kind] = await _registerCamera(kind, onRoute: false);
      _route[kind] = await _registerCamera(kind, onRoute: true);
    }
    car = await _registerCar();
    final finishBytes = await DestinationMarkerArt.png();
    finish = await registerBitmapImage(
      bitmap: finishBytes.buffer.asByteData(),
      imagePixelRatio: 2,
    );
    roadReport = await _registerRoadReport();
    for (final style in LocationMarkerStyle.values) {
      if (style == LocationMarkerStyle.classic) continue;
      final bytes = await LocationMarkerArt.png(style);
      _location[style] = await registerBitmapImage(
        bitmap: bytes.buffer.asByteData(),
        imagePixelRatio: 2,
      );
    }
  }

  static Future<ImageDescriptor> _registerCamera(
    CameraKind kind, {
    required bool onRoute,
  }) async {
    final bytes = await CameraMarkerArt.png(kind, onRoute: onRoute);
    return registerBitmapImage(
      bitmap: bytes.buffer.asByteData(),
      imagePixelRatio: 2,
    );
  }

  static Future<ImageDescriptor> _registerRoadReport() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = true;
    paint.color = Colors.white;
    canvas.drawCircle(const Offset(36, 34), 32, paint);
    paint.color = WaybiColors.ocean;
    canvas.drawCircle(const Offset(36, 34), 28, paint);
    paint.color = Colors.white;
    final path = Path()
      ..moveTo(36, 15)
      ..lineTo(54, 48)
      ..lineTo(18, 48)
      ..close();
    canvas.drawPath(path, paint);
    paint.color = WaybiColors.ocean;
    paint.strokeWidth = 4;
    paint.strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(36, 27), const Offset(36, 37), paint);
    canvas.drawCircle(const Offset(36, 43), 2.4, paint);
    final image = await recorder.endRecording().toImage(72, 72);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return registerBitmapImage(bitmap: bytes!, imagePixelRatio: 2);
  }

  static Future<ImageDescriptor> _registerCar() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = true;
    paint.color = Colors.white;
    canvas.drawCircle(const Offset(36, 36), 30, paint);
    paint.color = WaybiColors.deepOcean;
    canvas.drawCircle(const Offset(36, 36), 26, paint);
    paint.color = WaybiColors.sky;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(17, 29, 38, 19),
        const Radius.circular(5),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(24, 21, 24, 12),
        const Radius.circular(5),
      ),
      paint,
    );
    paint.color = WaybiColors.deepOcean;
    canvas.drawCircle(const Offset(25, 49), 4, paint);
    canvas.drawCircle(const Offset(47, 49), 4, paint);
    final image = await recorder.endRecording().toImage(72, 72);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return registerBitmapImage(bitmap: bytes!, imagePixelRatio: 2);
  }
}
