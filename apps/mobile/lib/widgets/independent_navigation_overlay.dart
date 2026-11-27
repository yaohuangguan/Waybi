import 'package:flutter/material.dart';

import '../domain/route_option.dart';
import '../drive/drive_engine.dart';
import '../drive/navigation_language.dart';
import '../providers/independent_navigation_engine.dart';
import 'navigation_overlay.dart';
import 'navigation_maneuver_icon.dart';

IconData independentManeuverIcon(RouteStepInfo? step) {
  final type = step?.maneuverType ?? '';
  // Preserve the existing circulation symbol; OSRM's modifier describes the
  // exit direction, not the direction of travel around the roundabout.
  if (type.contains('roundabout') || type == 'rotary') {
    return Icons.roundabout_left_rounded;
  }
  return navigationManeuverIcon(type, step?.maneuverModifier ?? '');
}

/// Independent-engine guidance on the shared navigation HUD.
///
/// Engine ticks update a [ValueNotifier] of [NavigationGuidance]; only the
/// turn banner and trip stats rebuild, and only when guidance actually
/// changed. The rest of the overlay rebuilds with its parent.
class IndependentNavigationOverlay extends StatefulWidget {
  const IndependentNavigationOverlay({
    super.key,
    required this.engine,
    required this.drive,
    required this.destination,
    required this.language,
    required this.onEnd,
    required this.onRecenter,
    required this.onOverview,
    this.following = true,
    this.overviewMode = false,
    required this.northUp,
    this.perspectiveTilted = false,
    required this.onCompassToggle,
    required this.onReport,
    required this.onSearchAlongRoute,
    required this.onDirections,
    required this.onShare,
    required this.onSettings,
    required this.onLayers,
    required this.onVoiceToggle,
    required this.onLanesToggle,
    required this.voiceEnabled,
    required this.lanesEnabled,
    this.gpsAccuracy,
    this.arrivalPanel,
    this.offlineReady = false,
    this.offlineCachedAt,
    this.systemStatus,
    this.onTopInsetChanged,
    this.onBottomInsetChanged,
  });
  final IndependentNavigationEngine engine;
  final DriveEngine drive;
  final String destination;
  final String language;
  final double? gpsAccuracy;
  final bool following;
  final bool overviewMode;
  final bool northUp;
  final bool perspectiveTilted;
  final bool voiceEnabled;
  final bool lanesEnabled;
  final Widget? arrivalPanel;
  final bool offlineReady;
  final DateTime? offlineCachedAt;
  final Widget? systemStatus;
  final ValueChanged<double>? onTopInsetChanged, onBottomInsetChanged;
  final VoidCallback onEnd,
      onRecenter,
      onOverview,
      onCompassToggle,
      onReport,
      onSearchAlongRoute,
      onDirections,
      onShare,
      onSettings,
      onLayers,
      onVoiceToggle,
      onLanesToggle;

  @override
  State<IndependentNavigationOverlay> createState() =>
      _IndependentNavigationOverlayState();
}

class _IndependentNavigationOverlayState
    extends State<IndependentNavigationOverlay> {
  late final ValueNotifier<NavigationGuidance> _guidance = ValueNotifier(
    _compute(),
  );
  late bool _offline = widget.engine.error != null;

  IndependentNavigationEngine get engine => widget.engine;
  DriveEngine get drive => widget.drive;
  String get language => widget.language;
  String get destination => widget.destination;

  @override
  void initState() {
    super.initState();
    engine.addListener(_changed);
    drive.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant IndependentNavigationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.engine, widget.engine)) {
      oldWidget.engine.removeListener(_changed);
      widget.engine.addListener(_changed);
    }
    if (!identical(oldWidget.drive, widget.drive)) {
      oldWidget.drive.removeListener(_changed);
      widget.drive.addListener(_changed);
    }
    _offline = engine.error != null;
    _guidance.value = _compute();
  }

  @override
  void dispose() {
    engine.removeListener(_changed);
    drive.removeListener(_changed);
    _guidance.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    _guidance.value = _compute();
    final offline = engine.error != null;
    if (offline != _offline) setState(() => _offline = offline);
  }

  String _text(String en, String zh) => language == 'zh' ? zh : en;

  String get _gpsStatus => switch (drive.gpsIssue) {
    NavigationGpsIssue.servicesDisabled => _text(
      'Turn on Location Services in Settings',
      '请在系统设置中开启定位服务',
    ),
    NavigationGpsIssue.permissionDenied => _text(
      'Allow location access for Waybi in Settings',
      '请在系统设置中允许 Waybi 使用定位',
    ),
    NavigationGpsIssue.unstable => _text(
      'GPS unstable · holding your last position',
      '定位不稳定，保留上次可靠位置',
    ),
    NavigationGpsIssue.stale => _text(
      'GPS signal lost · reconnecting',
      '定位信号中断，正在恢复',
    ),
    NavigationGpsIssue.unavailable => _text(
      'Location unavailable · retrying',
      '定位暂不可用，正在重试',
    ),
    _ => _text('Getting an accurate GPS fix…', '正在获取准确位置…'),
  };

  NavigationGuidance _compute() {
    final next = engine.nextStep;
    final status = engine.arrived
        ? _text('Arrived at $destination', '已抵达 $destination')
        : drive.locationIssue != null
        ? _gpsStatus
        : engine.rerouting
        ? _text('Updating route…', '正在重新规划路线…')
        : engine.offRoute
        ? _text('Off route · finding your way', '已偏离路线，正在更新')
        : engine.transitRestrictionAhead
        ? _text(
            'Bus-only road ahead · choose another route',
            '前方为公交专用路段，请选择其他路线',
          )
        : engine.error != null
        ? _text('Route update unavailable · retrying', '路线更新暂不可用，正在重试')
        : null;
    return NavigationGuidance(
      instruction: status ?? routeStepInstruction(next, language),
      thenInstruction: status == null && engine.followingStep != null
          ? routeStepInstruction(engine.followingStep, language)
          : null,
      maneuverIcon: engine.arrived
          ? Icons.flag_rounded
          : engine.rerouting || engine.offRoute
          ? Icons.alt_route_rounded
          : independentManeuverIcon(next),
      stepMeters: engine.offRoute || drive.locationIssue != null
          ? null
          : engine.distanceToStepMeters,
      remainingMeters: engine.remainingDistanceMeters,
      remainingSeconds: engine.remainingSeconds,
      lanes:
          engine.distanceToStepMeters <= 300 &&
              !engine.offRoute &&
              !engine.arrived
          ? routeNavigationLanes(next)
          : const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    return NavigationOverlay(
      onTopInsetChanged: widget.onTopInsetChanged,
      onBottomInsetChanged: widget.onBottomInsetChanged,
      engine: drive,
      language: language,
      guidanceListenable: _guidance,
      destinationTitle: destination,
      gpsAccuracy: widget.gpsAccuracy,
      voiceEnabled: widget.voiceEnabled,
      lanesEnabled: widget.lanesEnabled,
      onEnd: widget.onEnd,
      onRecenter: widget.onRecenter,
      onOverview: widget.onOverview,
      following: widget.following,
      overviewMode: widget.overviewMode,
      northUp: widget.northUp,
      perspectiveTilted: widget.perspectiveTilted,
      perspectiveAvailable: true,
      onCompassToggle: widget.onCompassToggle,
      onReport: widget.onReport,
      onSearchAlongRoute: widget.onSearchAlongRoute,
      onDirections: widget.onDirections,
      onShare: widget.onShare,
      onSettings: widget.onSettings,
      onLayers: widget.onLayers,
      onVoiceToggle: widget.onVoiceToggle,
      onLanesToggle: widget.onLanesToggle,
      arrivalPanel: widget.arrivalPanel,
      offlineReady: widget.offlineReady,
      usingOfflineGuidance: _offline,
      offlineCachedAt: widget.offlineCachedAt,
      systemStatus: widget.systemStatus,
    );
  }
}
