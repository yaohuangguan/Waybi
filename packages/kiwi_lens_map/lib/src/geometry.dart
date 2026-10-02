class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  bool get isValid =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      latitude == other.latitude &&
      longitude == other.longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

class MapViewportState {
  const MapViewportState({
    required this.center,
    this.zoom = 14,
    this.bearing = 0,
    this.pitch = 0,
  });

  final GeoPoint center;
  final double zoom;
  final double bearing;
  final double pitch;

  MapViewportState copyWith({
    GeoPoint? center,
    double? zoom,
    double? bearing,
    double? pitch,
  }) => MapViewportState(
    center: center ?? this.center,
    zoom: zoom ?? this.zoom,
    bearing: bearing ?? this.bearing,
    pitch: pitch ?? this.pitch,
  );
}

enum LocationMarkerStyle { kiwi, arrow, car, classic }

enum MapAppearance { standard, satellite, terrain, hybrid }
