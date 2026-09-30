import '../theme/tasman_theme.dart';

import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../drive/drive_engine.dart';
import 'road_event_timeline.dart';

const _ink = TasmanColors.darkOcean;
const _accent = TasmanColors.sky;

String navigationDistanceLabel(num? metres) {
  if (metres == null || !metres.isFinite) return '—';
  final safe = metres < 0 ? 0 : metres;
  if (safe >= 1000) return '${(safe / 1000).toStringAsFixed(1)} km';
  return '${safe.round()} m';
}

IconData _maneuverIcon(Maneuver? maneuver) {
  final name = maneuver?.name.toLowerCase() ?? '';
  if (name.contains('uturn')) return Icons.u_turn_left_rounded;
  if (name.contains('right')) return Icons.turn_right_rounded;
  if (name.contains('left')) return Icons.turn_left_rounded;
  if (name.contains('roundabout')) return Icons.roundabout_right_rounded;
  return Icons.straight_rounded;
}

class NavigationLane {
  const NavigationLane(this.symbol, this.recommended);
  final String symbol;
  final bool recommended;
}

/// Both providers feed the same Tasman HUD without manufacturing Google events.
class NavigationGuidance {
  const NavigationGuidance({
    required this.instruction,
    required this.maneuverIcon,
    this.stepMeters,
    this.remainingMeters,
    this.remainingSeconds,
    this.lanes = const [],
  });
  final String instruction;
  final IconData maneuverIcon;
  final num? stepMeters;
  final num? remainingMeters;
  final int? remainingSeconds;
  final List<NavigationLane> lanes;
}

class NavigationOverlay extends StatefulWidget {
  const NavigationOverlay({
    super.key,
    required this.engine,
    this.guidance,
    required this.destinationTitle,
    required this.gpsAccuracy,
    required this.voiceEnabled,
    required this.lanesEnabled,
    required this.onEnd,
    required this.onRecenter,
    required this.onOverview,
    required this.northUp,
    required this.onCompassToggle,
    required this.onReport,
    required this.onSearchAlongRoute,
    required this.onDirections,
    required this.onShare,
    required this.onSettings,
    required this.onLayers,
    required this.onVoiceToggle,
    required this.onLanesToggle,
  });

  final DriveEngine engine;
  final NavigationGuidance? guidance;
  final String destinationTitle;
  final double? gpsAccuracy;
  final bool voiceEnabled;
  final bool lanesEnabled;
  final VoidCallback onEnd;
  final VoidCallback onRecenter;
  final VoidCallback onOverview;
  final bool northUp;
  final VoidCallback onCompassToggle;
  final VoidCallback onReport;
  final VoidCallback onSearchAlongRoute;
  final VoidCallback onDirections;
  final VoidCallback onShare;
  final VoidCallback onSettings;
  final VoidCallback onLayers;
  final VoidCallback onVoiceToggle;
  final VoidCallback onLanesToggle;

  @override
  State<NavigationOverlay> createState() => _NavigationOverlayState();
}

class _NavigationOverlayState extends State<NavigationOverlay> {
  bool expanded = false;
  double _sheetDrag = 0;

  void _settleSheet(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final movement = _sheetDrag.abs() > 24 ? _sheetDrag : velocity / 12;
    if (movement.abs() > 24) setState(() => expanded = movement < 0);
    _sheetDrag = 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final nav = widget.engine.navInfo;
    final step = nav?.currentStep;
    final guidance =
        widget.guidance ??
        NavigationGuidance(
          instruction:
              step?.fullInstructions ??
              step?.fullRoadName ??
              'Continue on route',
          maneuverIcon: _maneuverIcon(step?.maneuver),
          stepMeters: nav?.distanceToCurrentStepMeters,
          remainingMeters: nav?.distanceToFinalDestinationMeters,
          remainingSeconds: nav?.timeToFinalDestinationSeconds,
          lanes: [
            for (final lane in step?.lanes ?? <Lane>[])
              NavigationLane(
                lane.laneDirections
                    .map((direction) {
                      final name = direction.laneShape.name.toLowerCase();
                      return name.contains('left')
                          ? '←'
                          : name.contains('right')
                          ? '→'
                          : '↑';
                    })
                    .toSet()
                    .join(),
                lane.laneDirections.any((direction) => direction.isRecommended),
              ),
          ],
        );
    final camera = widget.engine.upcomingCamera;
    final cameraDistance = widget.engine.upcomingCameraDistanceMeters;
    final remainingSeconds = guidance.remainingSeconds;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final arrival = remainingSeconds == null
        ? '—'
        : TimeOfDay.fromDateTime(
            DateTime.now().add(
              Duration(seconds: remainingSeconds.clamp(0, 86400)),
            ),
          ).format(context);
    final speeding =
        widget.engine.speedLimitKph != null &&
        widget.engine.speedKph > widget.engine.speedLimitKph!;

    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          Positioned(
            top: 10,
            left: 14,
            right: 14,
            child: PointerInterceptor(
              child: Container(
                padding: const EdgeInsets.fromLTRB(17, 15, 17, 15),
                decoration: BoxDecoration(
                  color: _ink,
                  borderRadius: BorderRadius.circular(23),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x36000000),
                      blurRadius: 18,
                      offset: Offset(0, 7),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(guidance.maneuverIcon, color: _accent, size: 40),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            navigationDistanceLabel(guidance.stepMeters),
                            style: const TextStyle(
                              color: _accent,
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            guidance.instruction,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(width: 1, height: 53, color: Colors.white30),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          arrival,
                          style: const TextStyle(
                            color: _accent,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          navigationDistanceLabel(guidance.remainingMeters),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.lanesEnabled && guidance.lanes.isNotEmpty)
            Positioned(
              top: 113,
              left: 14,
              right: 98,
              child: PointerInterceptor(
                child: Material(
                  color: _ink,
                  borderRadius: BorderRadius.circular(17),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 10,
                    ),
                    child: Wrap(
                      spacing: 7,
                      runSpacing: 5,
                      children: [
                        const Text(
                          'LANES',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        for (final lane in guidance.lanes)
                          Container(
                            constraints: const BoxConstraints(minWidth: 38),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: lane.recommended
                                  ? _accent
                                  : TasmanColors.darkSurface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              lane.symbol,
                              style: TextStyle(
                                color: lane.recommended ? _ink : Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 198,
            right: 14,
            child: PointerInterceptor(
              child: _NavigationControlRail(
                northUp: widget.northUp,
                onCompassToggle: widget.onCompassToggle,
                onRecenter: widget.onRecenter,
                onLayers: widget.onLayers,
                onReport: widget.onReport,
              ),
            ),
          ),
          Positioned(
            top: 218,
            left: 14,
            child: PointerInterceptor(
              child: Container(
                width: 84,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: _ink,
                  border: Border.all(
                    color: speeding ? const Color(0xFFFF6767) : Colors.white,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(color: Color(0x33000000), blurRadius: 14),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${widget.engine.speedKph.round()}',
                              style: TextStyle(
                                color: speeding
                                    ? const Color(0xFFFF6767)
                                    : _accent,
                                fontWeight: FontWeight.w900,
                                fontSize: 27,
                              ),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 5),
                          child: Text(
                            'km/h',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'LIMIT ${widget.engine.speedLimitKph ?? '—'}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (camera != null && cameraDistance != null)
            Positioned(
              left: 14,
              bottom: bottomInset + (expanded ? 344 : 212),
              child: PointerInterceptor(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 235),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: (dark ? TasmanColors.darkSurface : scheme.surface)
                        .withValues(alpha: .97),
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: .45),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x36000000),
                        blurRadius: 16,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircleAvatar(
                        backgroundColor: TasmanColors.ocean,
                        child: Icon(Icons.speed_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Camera · ${navigationDistanceLabel(cameraDistance)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              camera.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: PointerInterceptor(
              child: GestureDetector(
                key: const Key('navigationSheetSurface'),
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) => _sheetDrag = 0,
                onVerticalDragUpdate: (details) =>
                    _sheetDrag += details.delta.dy,
                onVerticalDragEnd: _settleSheet,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.bottomCenter,
                  child: Material(
                    color: dark ? TasmanColors.darkOcean : scheme.surface,
                    elevation: 0,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(27),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(14, 3, 14, bottomInset + 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            key: const Key('navigationSheetHandle'),
                            onTap: () => setState(() => expanded = !expanded),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Container(
                                width: 44,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: theme.dividerColor,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.destinationTitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              FilledButton.icon(
                                onPressed: widget.onEnd,
                                style: FilledButton.styleFrom(
                                  backgroundColor: TasmanColors.danger,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 9,
                                  ),
                                ),
                                icon: const Icon(Icons.stop_rounded, size: 18),
                                label: const Text('End'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: Row(
                              children: [
                                _TripStat(
                                  label: 'Cameras on route',
                                  value: '${widget.engine.routeCameraCount}',
                                ),
                                _TripStat(
                                  label: 'Distance',
                                  value: navigationDistanceLabel(
                                    guidance.remainingMeters,
                                  ),
                                ),
                                _TripStat(label: 'Arrival', value: arrival),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          if (widget.engine.upcomingRoadEvents.isNotEmpty) ...[
                            const SizedBox(height: TasmanSpacing.x2),
                            RoadEventTimeline(
                              events: widget.engine.upcomingRoadEvents,
                              dark: dark,
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _Chip(
                                icon: widget.voiceEnabled
                                    ? Icons.volume_up_rounded
                                    : Icons.volume_off_rounded,
                                label: widget.voiceEnabled
                                    ? 'Voice ✓'
                                    : 'Voice off',
                                onTap: widget.onVoiceToggle,
                              ),
                              const SizedBox(width: 6),
                              _Chip(
                                icon: Icons.alt_route_rounded,
                                label: widget.lanesEnabled
                                    ? 'Lanes ✓'
                                    : 'Lanes off',
                                onTap: widget.onLanesToggle,
                              ),
                              const SizedBox(width: 6),
                              _Chip(
                                icon: Icons.gps_fixed_rounded,
                                label: widget.gpsAccuracy == null
                                    ? 'GPS —'
                                    : 'GPS ±${widget.gpsAccuracy!.round()} m',
                              ),
                            ],
                          ),
                          if (expanded) ...[
                            const SizedBox(height: 15),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Trip tools',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const SizedBox(height: 9),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _ActionButton(
                                  icon: Icons.add_a_photo_rounded,
                                  label: 'Add a report',
                                  onTap: widget.onReport,
                                ),
                                _ActionButton(
                                  icon: Icons.share_rounded,
                                  label: 'Share ETA snapshot',
                                  onTap: widget.onShare,
                                ),
                                _ActionButton(
                                  icon: Icons.search_rounded,
                                  label: 'Search along route',
                                  onTap: widget.onSearchAlongRoute,
                                ),
                                _ActionButton(
                                  icon: Icons.route_rounded,
                                  label: 'Preview route',
                                  onTap: widget.onOverview,
                                ),
                                _ActionButton(
                                  icon: Icons.list_alt_rounded,
                                  label: 'Directions',
                                  onTap: widget.onDirections,
                                ),
                                _ActionButton(
                                  icon: Icons.settings_rounded,
                                  label: 'Settings',
                                  onTap: widget.onSettings,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripStat extends StatelessWidget {
  const _TripStat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 15,
            color: onTap == null ? scheme.onSurfaceVariant : scheme.primary,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onTap == null
                    ? scheme.onSurfaceVariant
                    : scheme.onSurface,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    return Expanded(
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.dividerColor),
        ),
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: content,
              ),
      ),
    );
  }
}

class _NavigationControlRail extends StatelessWidget {
  const _NavigationControlRail({
    required this.northUp,
    required this.onCompassToggle,
    required this.onRecenter,
    required this.onLayers,
    required this.onReport,
  });

  final bool northUp;
  final VoidCallback onCompassToggle;
  final VoidCallback onRecenter;
  final VoidCallback onLayers;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .97),
      elevation: 6,
      borderRadius: BorderRadius.circular(19),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RailButton(
            icon: northUp ? Icons.explore_rounded : Icons.navigation_rounded,
            tooltip: northUp
                ? 'North up · tap for follow view'
                : 'Follow view · tap for north up',
            onTap: onCompassToggle,
          ),
          const _RailDivider(),
          _RailButton(
            icon: Icons.my_location_rounded,
            tooltip: 'Recenter',
            onTap: onRecenter,
          ),
          const _RailDivider(),
          _RailButton(
            icon: Icons.layers_rounded,
            tooltip: 'Map layers',
            onTap: onLayers,
          ),
          const _RailDivider(),
          _RailButton(
            icon: Icons.add_alert_rounded,
            tooltip: 'Report road issue',
            onTap: onReport,
            iconColor: TasmanColors.danger,
            backgroundColor: Color(0xFFFFF3F1),
          ),
        ],
      ),
    );
  }
}

class _RailDivider extends StatelessWidget {
  const _RailDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 28, height: 1, color: TasmanColors.lightBorder);
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.iconColor,
    this.backgroundColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor ?? Colors.transparent,
      child: SizedBox(
        width: 46,
        height: 46,
        child: IconButton(
          padding: EdgeInsets.zero,
          onPressed: onTap,
          tooltip: tooltip,
          iconSize: 21,
          icon: Icon(icon, color: iconColor ?? TasmanColors.darkOcean),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 48) / 2,
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(color: theme.dividerColor),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: scheme.primary, size: 19),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
