import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/geo_math.dart';
import '../domain/route_option.dart';
import '../drive/drive_engine.dart';
import '../drive/navigation_language.dart';
import '../drive/route_camera_matcher.dart';
import '../domain/map_provider.dart';

/// Where the Plus offline corridor is stored.
const offlineCorridorKey = 'waybi.navigation.offline_corridor.v1';

/// Saves the next 6 km of [route] (geometry, maneuvers, cameras and road
/// events, from the drive engine's progress) so guidance can continue
/// through a dead zone.
Future<void> saveOfflineCorridor({
  required RouteOption route,
  required DriveEngine drive,
  required String destination,
  required String language,
  required DateTime now,
}) async {
  final start = drive.routeProgress?.alongMeters ?? 0.0;
  final end = start + 6000;
  final corridor = <GeoPoint>[];
  var travelled = 0.0;
  for (var index = 0; index < route.points.length - 1; index++) {
    final a = route.points[index];
    final b = route.points[index + 1];
    final segment = distanceMeters(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
    final segmentEnd = travelled + segment;
    if (segmentEnd >= start - 100 && travelled <= end + 100) {
      if (corridor.isEmpty) corridor.add(a);
      corridor.add(b);
    }
    travelled = segmentEnd;
    if (travelled > end + 100) break;
  }
  final matcher = const RouteCameraMatcher();
  final steps = <Map<String, Object?>>[];
  for (final step in route.steps) {
    final along = matcher.project(step.location, route.points)?.alongMeters;
    if (along == null || along < start - 50 || along > end) continue;
    steps.add({
      'instruction': routeStepInstruction(step, language),
      'roadName': step.roadName,
      'maneuverType': step.maneuverType,
      'maneuverModifier': step.maneuverModifier,
      'distanceMeters': step.distanceMeters,
      'alongMeters': along,
      'latitude': step.location.latitude,
      'longitude': step.location.longitude,
    });
  }
  final cameras = [
    for (final match in drive.routeCameras)
      if (match.alongMeters >= start - 50 && match.alongMeters <= end)
        {
          'id': match.camera.id,
          'type': match.camera.type,
          'location': match.camera.location,
          'latitude': match.camera.latitude,
          'longitude': match.camera.longitude,
          'alongMeters': match.alongMeters,
        },
  ];
  final events = [
    for (final event in drive.upcomingRoadEvents)
      if ((event.distanceFromDriver ?? double.infinity) <= 6000)
        {
          'id': event.id,
          'type': event.type.name,
          'roadName': event.roadName,
          'latitude': event.location.latitude,
          'longitude': event.location.longitude,
          'distanceFromDriver': event.distanceFromDriver,
          'distanceAlongRoute': event.distanceAlongRoute,
          'severity': event.severity.name,
        },
  ];
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    offlineCorridorKey,
    jsonEncode({
      'cachedAt': now.toIso8601String(),
      'destination': destination,
      'routeId': route.id,
      'fromAlongMeters': start,
      'aheadMeters': 6000,
      'geometry': [
        for (final point in corridor) [point.latitude, point.longitude],
      ],
      'steps': steps,
      'cameras': cameras,
      'roadEvents': events,
    }),
  );
}
