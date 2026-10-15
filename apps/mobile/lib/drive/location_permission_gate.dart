import 'package:permission_handler/permission_handler.dart';

/// Shares an open OS permission sheet across startup, resume and navigation.
/// Passive recovery checks access without repeatedly asking after a denial.
class LocationPermissionGate {
  LocationPermissionGate({
    Future<PermissionStatus> Function()? read,
    Future<PermissionStatus> Function()? request,
  }) : _read = read ?? (() => Permission.locationWhenInUse.status),
       _request = request ?? (() => Permission.locationWhenInUse.request());

  final Future<PermissionStatus> Function() _read;
  final Future<PermissionStatus> Function() _request;
  Future<PermissionStatus>? _pending;

  Future<PermissionStatus> ensure({bool requestPermission = true}) async {
    final pending = _pending;
    if (pending != null) return pending;
    final status = await _read();
    final inFlight = _pending;
    if (inFlight != null) return inFlight;
    if (!requestPermission || !status.isDenied) return status;

    final next = _request();
    _pending = next;
    try {
      return await next;
    } finally {
      if (identical(_pending, next)) _pending = null;
    }
  }
}
