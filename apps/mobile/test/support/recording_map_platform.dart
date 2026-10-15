import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

class RecordingMapPlatform extends ml.MapLibrePlatform {
  int builds = 0;
  bool initialized = false;
  EdgeInsets padding = EdgeInsets.zero;
  final updates = <String>[];
  final sources = <String, Map<String, dynamic>>{};
  final moves = <ml.CameraUpdate>[];
  List<Map<String, dynamic>> features = [];
  ml.CameraPosition camera = const ml.CameraPosition(
    target: ml.LatLng(-36.85, 174.76),
    zoom: 15,
    bearing: 95,
  );
  int cameraReads = 0;
  @override
  Future<ml.CameraPosition?> queryCameraPosition() async {
    cameraReads++;
    return camera;
  }

  @override
  Widget buildView(
    Map<String, dynamic> creationParams,
    void Function(int) onCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestures,
  ) {
    builds++;
    if (!initialized) {
      initialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => onCreated(0));
    }
    return const ColoredBox(color: Colors.grey);
  }

  @override
  Future<void> initPlatform(int id) async {}
  @override
  Future<ml.CameraPosition?> updateMapOptions(
    Map<String, dynamic> options,
  ) async => null;
  @override
  Future<bool?> moveCamera(ml.CameraUpdate cameraUpdate) async {
    moves.add(cameraUpdate);
    return true;
  }

  @override
  Future<bool> easeCamera(
    ml.CameraUpdate cameraUpdate, {
    Duration? duration,
    ml.CameraAnimationInterpolation? interpolation,
  }) async {
    moves.add(cameraUpdate);
    return true;
  }

  @override
  Future<void> updateContentInsets(EdgeInsets insets, bool animated) async {
    padding = insets;
  }

  @override
  Future<void> setGeoJsonSource(String id, Map<String, dynamic> data) async {
    updates.add(id);
    sources[id] = data;
  }

  @override
  Future<List> getLayerIds() async => const [];

  @override
  Future<List> queryRenderedFeaturesInRect(
    Rect rect,
    List<String> layers,
    String? filter,
  ) async => features;
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
