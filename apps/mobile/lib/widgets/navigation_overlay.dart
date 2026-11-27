import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../domain/navigation_lanes.dart';
import '../domain/route_option.dart';
import '../drive/drive_engine.dart';
import '../drive/navigation_language.dart';
import '../theme/waybi_theme.dart';
import 'driving_motion.dart';
import 'hold_to_end_button.dart';
import 'lane_arrow.dart';
import 'navigation_camera_alert.dart';
import 'navigation_maneuver_icon.dart';
import 'navigation_transit_alert.dart';
import 'road_event_timeline.dart';
import 'speed_readout.dart';
import 'waybi_bird.dart';

const _ink = WaybiInk.surface;
const _accent = WaybiInk.accent;

/// HUD text is already in the driving type scale; very large system text
/// scales are capped here so the map stays visible.
const _hudMaxTextScale = 1.6;

@immutable
class NavigationLane {
  const NavigationLane(this.directions, this.recommended);
  final Set<LaneArrowDirection> directions;
  final bool recommended;

  @override
  bool operator ==(Object other) =>
      other is NavigationLane &&
      other.recommended == recommended &&
      setEquals(other.directions, directions);

  @override
  int get hashCode =>
      Object.hash(recommended, Object.hashAllUnordered(directions));
}

List<NavigationLane> routeNavigationLanes(RouteStepInfo? step) => [
  for (final lane in step?.lanes ?? const <RouteLane>[])
    NavigationLane(
      laneDirections(lane.indications),
      lane.recommended &&
          (laneDirections(lane.indications).isEmpty ||
              laneSupportsManeuver(lane.indications, step!.maneuverModifier)),
    ),
];

/// Both providers feed the same Waybi HUD without manufacturing Google events.
///
/// Value-equal guidance compares equal, so a [ValueNotifier] of it only
/// notifies when something visible changed.
@immutable
class NavigationGuidance {
  const NavigationGuidance({
    required this.instruction,
    required this.maneuverIcon,
    this.stepMeters,
    this.remainingMeters,
    this.remainingSeconds,
    this.lanes = const [],
    this.lanesImage,
    this.thenInstruction,
  });
  final String instruction;
  final IconData maneuverIcon;
  final num? stepMeters;
  final num? remainingMeters;
  final int? remainingSeconds;
  final List<NavigationLane> lanes;
  final ImageDescriptor? lanesImage;
  final String? thenInstruction;

  @override
  bool operator ==(Object other) =>
      other is NavigationGuidance &&
      other.instruction == instruction &&
      other.maneuverIcon == maneuverIcon &&
      other.stepMeters == stepMeters &&
      other.remainingMeters == remainingMeters &&
      other.remainingSeconds == remainingSeconds &&
      listEquals(other.lanes, lanes) &&
      identical(other.lanesImage, lanesImage) &&
      other.thenInstruction == thenInstruction;

  @override
  int get hashCode => Object.hash(
    instruction,
    maneuverIcon,
    stepMeters,
    remainingMeters,
    remainingSeconds,
    Object.hashAll(lanes),
    lanesImage,
    thenInstruction,
  );
}

class NavigationOverlay extends StatefulWidget {
  const NavigationOverlay({
    super.key,
    required this.engine,
    this.guidance,
    this.guidanceListenable,
    this.onTopInsetChanged,
    this.onBottomInsetChanged,
    this.language = 'en',
    required this.destinationTitle,
    required this.gpsAccuracy,
    required this.voiceEnabled,
    required this.lanesEnabled,
    required this.onEnd,
    required this.onRecenter,
    required this.onOverview,
    this.following = true,
    this.overviewMode = false,
    required this.northUp,
    this.perspectiveTilted = false,
    this.perspectiveAvailable = true,
    required this.onCompassToggle,
    required this.onReport,
    required this.onSearchAlongRoute,
    required this.onDirections,
    required this.onShare,
    required this.onSettings,
    required this.onLayers,
    required this.onVoiceToggle,
    required this.onLanesToggle,
    this.arrivalPanel,
    this.offlineReady = false,
    this.usingOfflineGuidance = false,
    this.offlineCachedAt,
    this.systemStatus,
  });

  /// Speed, cameras, road events and (without [guidance]) native guidance.
  /// Only the parts that show them rebuild when it notifies.
  final DriveEngine engine;

  /// Fixed guidance. Prefer [guidanceListenable] for guidance that changes
  /// with every fix, so only the turn banner and trip stats rebuild.
  final NavigationGuidance? guidance;
  final ValueListenable<NavigationGuidance>? guidanceListenable;

  /// Reported once the header's height has settled (not on every frame of
  /// an animation or every engine tick).
  final ValueChanged<double>? onTopInsetChanged;

  /// Reported once the trip deck rests at its compact or expanded height.
  final ValueChanged<double>? onBottomInsetChanged;
  final String language;
  final String destinationTitle;
  final double? gpsAccuracy;
  final bool voiceEnabled;
  final bool lanesEnabled;

  /// Called after the driver holds "End" (or confirms it with a screen
  /// reader). A short tap never ends navigation.
  final VoidCallback onEnd;
  final VoidCallback onRecenter;
  final VoidCallback onOverview;
  final bool following;
  final bool overviewMode;
  final bool northUp;
  final bool perspectiveTilted;
  final bool perspectiveAvailable;
  final VoidCallback onCompassToggle;
  final VoidCallback onReport;
  final VoidCallback onSearchAlongRoute;
  final VoidCallback onDirections;
  final VoidCallback onShare;
  final VoidCallback onSettings;
  final VoidCallback onLayers;
  final VoidCallback onVoiceToggle;
  final VoidCallback onLanesToggle;

  /// Shown in the expanded deck. It can read [DrivingMotion] to simplify
  /// itself while the car is moving.
  final Widget? arrivalPanel;
  final bool offlineReady;
  final bool usingOfflineGuidance;
  final DateTime? offlineCachedAt;
  final Widget? systemStatus;

  @override
  State<NavigationOverlay> createState() => _NavigationOverlayState();
}

class _NavigationOverlayState extends State<NavigationOverlay> {
  bool expanded = false;
  bool _passengerTools = false;
  double _compactDeckHeight = 124;
  double? _reportedBottom;
  double? _reportedInset;
  double _headerHeight = 0;
  final _sheetController = DraggableScrollableController();
  double _minExtent = .25;
  double _maxExtent = .45;
  late final ValueNotifier<bool> _moving = ValueNotifier(
    DrivingMotion.next(false, widget.engine.speedKph),
  );
  ImageDescriptor? _laneDescriptor;
  Future<Image?>? _laneImage;

  String _text(String en, String zh) => widget.language == 'zh' ? zh : en;

  @override
  void initState() {
    super.initState();
    widget.engine.addListener(_trackMotion);
  }

  @override
  void didUpdateWidget(covariant NavigationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.engine, widget.engine)) {
      oldWidget.engine.removeListener(_trackMotion);
      widget.engine.addListener(_trackMotion);
      _trackMotion();
    }
  }

  @override
  void dispose() {
    widget.engine.removeListener(_trackMotion);
    _moving.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  void _trackMotion() {
    _moving.value = DrivingMotion.next(_moving.value, widget.engine.speedKph);
  }

  /// A finger is on the trip deck: its size is not final until release.
  bool _deckTouched = false;
  Size? _deckSize;

  void _deckTouch(bool down) {
    _deckTouched = down;
    if (!down) {
      // The release may need no snap; report what the deck settled at.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final size = _deckSize;
        if (size != null) _deckSettled(size);
      });
    }
  }

  void _headerSettled(Size size) {
    if (!mounted) return;
    final inset = size.height + 22 + MediaQuery.paddingOf(context).top;
    if ((size.height - _headerHeight).abs() >= 1) {
      setState(() => _headerHeight = size.height);
    }
    if (_reportedInset == null || (inset - _reportedInset!).abs() >= 1) {
      _reportedInset = inset;
      widget.onTopInsetChanged?.call(inset);
    }
  }

  void _deckSettled(Size size) {
    _deckSize = size;
    // Mid-drag sizes are never reported; the sheet snaps to rest.
    if (!mounted || _deckTouched) return;
    final inset = size.height + 14;
    if (_reportedBottom == null || (inset - _reportedBottom!).abs() >= 1) {
      setState(() => _reportedBottom = inset);
      widget.onBottomInsetChanged?.call(inset);
    }
  }

  void _compactSettled(Size size) {
    if (!mounted || expanded) return;
    if ((size.height - _compactDeckHeight).abs() < 1) return;
    final atMinimum =
        _sheetController.isAttached &&
        (_sheetController.size - _minExtent).abs() < .002;
    setState(() => _compactDeckHeight = size.height);
    // A sheet that has been dragged keeps its previous extent when its
    // content shrinks. Keep a resting compact sheet fitted to that content.
    if (atMinimum) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !expanded && _sheetController.isAttached) {
          _sheetController.jumpTo(_minExtent);
        }
      });
    }
  }

  Future<void> _toggleSheet() async {
    final next = !expanded;
    final target = next ? _maxExtent : _minExtent;
    if (MediaQuery.disableAnimationsOf(context)) {
      _sheetController.jumpTo(target);
    } else {
      await _sheetController.animateTo(
        target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
    // Header controls can change the available extent while opening. When
    // closing, the controller may already be at its new minimum and emit no
    // notification; preserve the user's tap intent in that case as well.
    if (mounted) setState(() => expanded = next);
  }

  String _offlineAge() {
    final cachedAt = widget.offlineCachedAt;
    if (cachedAt == null) return '';
    final age = DateTime.now().difference(cachedAt);
    if (age.inSeconds < 20) return _text('updated just now', '刚刚更新');
    if (age.inMinutes < 1) {
      return _text('${age.inSeconds}s old', '${age.inSeconds} 秒前更新');
    }
    return _text('${age.inMinutes}m old', '${age.inMinutes} 分钟前更新');
  }

  String _distance(num? metres) => metres == null || !metres.isFinite
      ? '—'
      : navigationMetres(metres, widget.language);

  NavigationGuidance _nativeGuidance() {
    final nav = widget.engine.navInfo;
    final step = nav?.currentStep;
    return NavigationGuidance(
      instruction: nav?.navState == NavState.rerouting
          ? _text('Updating route…', '正在重新规划路线…')
          : navigationInstruction(step, widget.language),
      lanesImage: step?.lanesImage,
      maneuverIcon: navigationManeuverIcon(step?.maneuver.name ?? ''),
      stepMeters: nav?.distanceToCurrentStepMeters,
      remainingMeters: nav?.distanceToFinalDestinationMeters,
      remainingSeconds: nav?.timeToFinalDestinationSeconds,
      lanes: [
        for (final lane in step?.lanes ?? <Lane>[])
          NavigationLane(
            laneDirections(lane.laneDirections.map((d) => d.laneShape.name)),
            lane.laneDirections.any(
              (direction) =>
                  direction.isRecommended &&
                  (laneDirections(
                        lane.laneDirections.map((d) => d.laneShape.name),
                      ).isEmpty ||
                      laneSupportsManeuver([
                        direction.laneShape.name,
                      ], step!.maneuver.name)),
            ),
          ),
      ],
    );
  }

  NavigationGuidance _currentGuidance() =>
      widget.guidanceListenable?.value ?? widget.guidance ?? _nativeGuidance();

  /// The listenables guidance depends on: its notifier, or the engine for
  /// native guidance.
  Listenable get _guidanceSource =>
      widget.guidanceListenable ??
      (widget.guidance == null ? widget.engine : const _Never());

  String _arrival(BuildContext context, int? remainingSeconds) =>
      remainingSeconds == null
      ? '—'
      : TimeOfDay.fromDateTime(
          DateTime.now().add(
            Duration(seconds: remainingSeconds.clamp(0, 86400)),
          ),
        ).format(context);

  Widget _guidanceHeader(BuildContext context, NavigationGuidance guidance) {
    final type = context.driveType;
    final showLanes =
        widget.lanesEnabled &&
        guidance.stepMeters != null &&
        guidance.stepMeters! <= 300 &&
        (guidance.lanes.any((lane) => lane.recommended) ||
            guidance.lanesImage != null);
    if (guidance.lanesImage != _laneDescriptor) {
      _laneDescriptor = guidance.lanesImage;
      _laneImage = _laneDescriptor == null
          ? null
          : getRegisteredImage(_laneDescriptor!).catchError((Object _) => null);
    }
    return Container(
      key: const ValueKey('navigationGuidanceHeader'),
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(guidance.maneuverIcon, color: _accent, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _distance(guidance.stepMeters),
                      style: type.distance.copyWith(color: _accent),
                    ),
                    Text(
                      guidance.instruction,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: type.instruction.copyWith(color: WaybiInk.text),
                    ),
                    if (guidance.thenInstruction != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${_text('Then', '然后')} · ${guidance.thenInstruction}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: type.secondary.copyWith(color: _accent),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // The ETA column may shrink so the instruction keeps its width.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * .26,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _arrival(context, guidance.remainingSeconds),
                        style: type.value.copyWith(
                          color: _accent,
                          fontSize: 20,
                        ),
                      ),
                      Text(
                        _distance(guidance.remainingMeters),
                        style: type.secondary.copyWith(color: WaybiInk.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (showLanes) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(color: WaybiInk.border, height: 1),
            ),
            Row(
              children: [
                Text(
                  _text('USE LANE', '推荐车道'),
                  style: type.label.copyWith(color: WaybiInk.muted),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: guidance.lanes.isNotEmpty
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Row(
                            children: [
                              for (
                                var index = 0;
                                index < guidance.lanes.length;
                                index++
                              )
                                Semantics(
                                  label: _text(
                                    'Lane ${index + 1}',
                                    '第 ${index + 1} 车道',
                                  ),
                                  selected: guidance.lanes[index].recommended,
                                  child: Container(
                                    key: ValueKey('navigation-lane-$index'),
                                    margin: const EdgeInsets.only(left: 5),
                                    constraints: const BoxConstraints(
                                      minWidth: 42,
                                    ),
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: guidance.lanes[index].recommended
                                          ? _accent
                                          : WaybiInk.raised,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: LaneArrow(
                                      directions:
                                          guidance.lanes[index].directions,
                                      language: widget.language,
                                      color: guidance.lanes[index].recommended
                                          ? _ink
                                          : WaybiInk.muted,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        )
                      : SizedBox(
                          height: 43,
                          child: FutureBuilder<Image?>(
                            future: _laneImage,
                            builder: (_, snapshot) => snapshot.data == null
                                ? const SizedBox.shrink()
                                : FittedBox(
                                    fit: BoxFit.contain,
                                    child: snapshot.data!,
                                  ),
                          ),
                        ),
                ),
              ],
            ),
            if (guidance.lanes.any((lane) => lane.directions.isEmpty))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _text('Some lane directions unavailable', '部分车道方向暂缺'),
                  key: const Key('navigationLaneDataNotice'),
                  style: type.notice.copyWith(color: WaybiInk.muted),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _notices() {
    final cameraNotice = upcomingNavigationCamera(widget.engine);
    final transitNotice = widget.engine.upcomingTransitLane;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (cameraNotice != null) ...[
          const SizedBox(height: 8),
          PointerInterceptor(
            child: NavigationCameraAlert(
              notice: cameraNotice,
              language: widget.language,
            ),
          ),
        ],
        if (transitNotice != null && cameraNotice == null) ...[
          const SizedBox(height: 8),
          PointerInterceptor(
            child: NavigationTransitAlert(
              notice: transitNotice,
              language: widget.language,
            ),
          ),
        ],
      ],
    );
  }

  Widget _tripStats(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.engine, _guidanceSource]),
    builder: (context, _) {
      final guidance = _currentGuidance();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            _TripStat(
              label: _text('Cameras on route', '沿途摄像头'),
              value: '${widget.engine.routeCameraCount}',
            ),
            _TripStat(
              label: _text('Distance', '剩余距离'),
              value: _distance(guidance.remainingMeters),
            ),
            _TripStat(
              label: _text('Arrival', '预计到达'),
              value: _arrival(context, guidance.remainingSeconds),
            ),
          ],
        ),
      );
    },
  );

  Widget _tripTools(BuildContext context) {
    final moving = DrivingMotion.of(context);
    final limited = moving && !_passengerTools;
    final tools = <(IconData, String, VoidCallback, bool)>[
      (
        Icons.add_a_photo_rounded,
        _text('Add a report', '添加上报'),
        widget.onReport,
        true,
      ),
      (
        Icons.share_rounded,
        _text('Share ETA snapshot', '分享预计到达'),
        widget.onShare,
        false,
      ),
      (
        Icons.search_rounded,
        _text('Search along route', '沿途搜索'),
        widget.onSearchAlongRoute,
        false,
      ),
      (
        Icons.route_rounded,
        _text('Preview route', '路线总览'),
        widget.onOverview,
        true,
      ),
      (
        Icons.list_alt_rounded,
        _text('Directions', '路线步骤'),
        widget.onDirections,
        true,
      ),
      (
        Icons.settings_rounded,
        _text('Settings', '设置'),
        widget.onSettings,
        false,
      ),
    ];
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _text('Trip tools', '行程工具'),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tool in tools)
              if (!limited || tool.$4)
                _ActionButton(icon: tool.$1, label: tool.$2, onTap: tool.$3),
          ],
        ),
        if (limited) ...[
          const SizedBox(height: 10),
          Container(
            key: const Key('navigationToolsLocked'),
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lock_clock_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _text(
                          'Sharing, search and settings unlock when you stop.',
                          '停车后可使用分享、搜索和设置。',
                        ),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: WaybiTextSize.caption,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    key: const Key('navigationPassengerUnlock'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, WaybiTouch.minTarget),
                    ),
                    onPressed: () => setState(() => _passengerTools = true),
                    child: Text(_text('I’m a passenger', '我是乘客')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _deck(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  expanded: expanded,
                  label: expanded
                      ? _text('Collapse trip details', '收起行程详情')
                      : _text('Expand trip details', '展开行程详情'),
                  child: InkWell(
                    key: const Key('navigationSheetHandle'),
                    onTap: _toggleSheet,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: WaybiTouch.minTarget,
                      ),
                      child: Row(
                        children: [
                          const WaybiBird(size: 28),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.destinationTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Icon(
                            expanded
                                ? Icons.expand_more_rounded
                                : Icons.expand_less_rounded,
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              HoldToEndButton(
                key: const Key('navigationEndButton'),
                label: _text('End', '结束'),
                holdHint: _text('Hold to end', '长按结束'),
                confirmTitle: _text('End navigation?', '结束导航？'),
                confirmAction: _text('End', '结束'),
                cancelAction: _text('Keep navigating', '继续导航'),
                onEnd: widget.onEnd,
              ),
            ],
          ),
        ),
        if (widget.arrivalPanel != null) ...[
          const SizedBox(height: 10),
          if (expanded)
            widget.arrivalPanel!
          else
            InkWell(
              key: const Key('arrivalSummary'),
              onTap: () => _toggleSheet(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: WaybiTouch.minTarget,
                ),
                child: Row(
                  children: [
                    Icon(Icons.flag_rounded, size: 20, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _text(
                          'Almost there · arrival & parking',
                          '快到了 · 查看到达与停车信息',
                        ),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.expand_less_rounded, size: 20),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 8),
        const Divider(height: 1),
        if (expanded)
          ListenableBuilder(
            listenable: widget.engine,
            builder: (context, _) {
              final notice = widget.engine.upcomingTransitLane;
              if (notice == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: NavigationTransitAlert(
                  notice: notice,
                  language: widget.language,
                  compact: true,
                ),
              );
            },
          ),
        _tripStats(context),
        const Divider(height: 1),
        ListenableBuilder(
          listenable: widget.engine,
          builder: (context, _) {
            final events = widget.engine.upcomingRoadEvents;
            if (events.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: WaybiSpacing.x2),
              child: RoadEventTimeline(
                events: events,
                language: widget.language,
                dark: dark,
                compact: !expanded,
              ),
            );
          },
        ),
        if (expanded && widget.systemStatus != null) widget.systemStatus!,
        if (expanded && widget.offlineReady) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: widget.usingOfflineGuidance
                  ? context.status.warningContainer
                  : scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Row(
              children: [
                Icon(
                  widget.usingOfflineGuidance
                      ? Icons.signal_wifi_connected_no_internet_4_rounded
                      : Icons.offline_pin_rounded,
                  size: 18,
                  color: widget.usingOfflineGuidance
                      ? context.status.onWarningContainer
                      : scheme.primary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    widget.usingOfflineGuidance
                        ? _text(
                            'Weak signal · cached guidance · ${_offlineAge()}',
                            '信号较弱 · 使用缓存导航 · ${_offlineAge()}',
                          )
                        : _text(
                            'Next 6 km cached · ${_offlineAge()}',
                            '前方约 6 公里已缓存 · ${_offlineAge()}',
                          ),
                    style: TextStyle(
                      color: widget.usingOfflineGuidance
                          ? context.status.onWarningContainer
                          : scheme.onSurfaceVariant,
                      fontSize: WaybiTextSize.caption,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (expanded) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              _Chip(
                icon: widget.voiceEnabled
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                label: widget.voiceEnabled
                    ? _text('Voice ✓', '语音 ✓')
                    : _text('Voice off', '语音关闭'),
                toggled: widget.voiceEnabled,
                onTap: widget.onVoiceToggle,
              ),
              const SizedBox(width: 6),
              _Chip(
                icon: Icons.alt_route_rounded,
                label: widget.lanesEnabled
                    ? _text('Lanes ✓', '车道 ✓')
                    : _text('Lanes off', '车道关闭'),
                toggled: widget.lanesEnabled,
                onTap: widget.onLanesToggle,
              ),
              const SizedBox(width: 6),
              _Chip(
                icon: Icons.gps_fixed_rounded,
                label: widget.gpsAccuracy == null
                    ? 'GPS —'
                    : 'GPS ±${widget.gpsAccuracy!.round()} ${_text('m', '米')}',
              ),
            ],
          ),
          const SizedBox(height: 15),
          _tripTools(context),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final header = _guidanceSourceBuilder(
      (context, guidance) => _guidanceHeader(context, guidance),
    );

    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Split-screen and keyboard-shortened windows can be shorter than
          // 333 pt; the upper bound must never fall below the lower one.
          final height = math.max(1.0, constraints.maxHeight);
          final upper = math.max(150.0, height * .45);
          final maxHeight = math.min(
            height,
            (height - _headerHeight - 170).clamp(150.0, upper),
          );
          _maxExtent = (maxHeight / height).clamp(.05, 1.0);
          _minExtent =
              ((_compactDeckHeight + bottomInset + 15).clamp(
                        96.0,
                        math.max(96.0, maxHeight - 1),
                      ) /
                      height)
                  .clamp(.05, _maxExtent);
          return ValueListenableBuilder<bool>(
            valueListenable: _moving,
            builder: (context, moving, child) =>
                DrivingMotion(moving: moving, child: child!),
            child: Stack(
              children: [
                Positioned(
                  top: 10,
                  left: 14,
                  right: 14,
                  child: _SettledSize(
                    onSettled: _headerSettled,
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: _hudMaxTextScale,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PointerInterceptor(
                            child: reduceMotion
                                ? header
                                : AnimatedSize(
                                    duration: const Duration(milliseconds: 220),
                                    alignment: Alignment.topCenter,
                                    child: header,
                                  ),
                          ),
                          ListenableBuilder(
                            listenable: widget.engine,
                            builder: (context, _) => _notices(),
                          ),
                          if (!expanded) ...[
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                PointerInterceptor(
                                  child: ListenableBuilder(
                                    listenable: widget.engine,
                                    builder: (context, _) => _SpeedCluster(
                                      speedKph: widget.engine.speedKph,
                                      limitKph: widget.engine.speedLimitKph,
                                      language: widget.language,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                PointerInterceptor(
                                  child: _NavigationControlRail(
                                    language: widget.language,
                                    following: widget.following,
                                    overviewMode: widget.overviewMode,
                                    northUp: widget.northUp,
                                    perspectiveTilted: widget.perspectiveTilted,
                                    perspectiveAvailable:
                                        widget.perspectiveAvailable,
                                    onCompassToggle: widget.onCompassToggle,
                                    onRecenter: widget.onRecenter,
                                    onOverview: widget.onOverview,
                                    onLayers: widget.onLayers,
                                    onReport: widget.onReport,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                // Keep the deck visually attached to the physical screen
                // edge. This also masks transient sub-pixel gaps while the
                // draggable sheet animates between extents.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: bottomInset + 44,
                  child: IgnorePointer(
                    child: ColoredBox(color: scheme.surface),
                  ),
                ),
                if (!expanded)
                  AnimatedPositioned(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    left: 14,
                    bottom:
                        (_reportedBottom ??
                            (_compactDeckHeight + bottomInset + 29)) +
                        12,
                    child: PointerInterceptor(
                      child: Material(
                        key: const Key('navigationRecenterButton'),
                        color: scheme.surface.withValues(alpha: .98),
                        elevation: 6,
                        borderRadius: BorderRadius.circular(28),
                        child: widget.following && !widget.overviewMode
                            ? IconButton(
                                tooltip: _text('Re-center', '回正导航'),
                                onPressed: widget.onRecenter,
                                icon: const Icon(Icons.my_location_rounded),
                                color: scheme.primary,
                              )
                            : TextButton.icon(
                                onPressed: widget.onRecenter,
                                icon: const Icon(
                                  Icons.navigation_rounded,
                                  size: 20,
                                ),
                                label: Text(_text('Re-center', '回到当前位置')),
                                style: TextButton.styleFrom(
                                  foregroundColor: scheme.primary,
                                  minimumSize: const Size(
                                    0,
                                    WaybiTouch.minTarget,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) => _deckTouch(true),
                    onPointerUp: (_) => _deckTouch(false),
                    onPointerCancel: (_) => _deckTouch(false),
                    child: NotificationListener<DraggableScrollableNotification>(
                      onNotification: (notification) {
                        // On short screens the header can leave only a tiny
                        // resize range. Tapping the handle must still reveal
                        // the scrollable trip tools when that range is below
                        // 1%.
                        final threshold = ((_maxExtent - _minExtent) / 2).clamp(
                          0.0,
                          .01,
                        );
                        final open =
                            notification.extent > _minExtent + threshold;
                        if (open != expanded) setState(() => expanded = open);
                        return false;
                      },
                      child: DraggableScrollableSheet(
                        controller: _sheetController,
                        expand: false,
                        initialChildSize: _minExtent,
                        minChildSize: _minExtent,
                        maxChildSize: _maxExtent,
                        snap: true,
                        snapAnimationDuration: reduceMotion
                            ? const Duration(milliseconds: 1)
                            : const Duration(milliseconds: 180),
                        shouldCloseOnMinExtent: false,
                        builder: (context, scrollController) => _SettledSize(
                          onSettled: _deckSettled,
                          child: PointerInterceptor(
                            child: Material(
                              color: scheme.surface,
                              elevation: 0,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(27),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: SingleChildScrollView(
                                key: const Key('navigationSheetSurface'),
                                controller: scrollController,
                                physics: const ClampingScrollPhysics(),
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    14,
                                    3,
                                    14,
                                    bottomInset + 12,
                                  ),
                                  child: _SettledSize(
                                    onSettled: _compactSettled,
                                    child: _deck(context),
                                  ),
                                ),
                              ),
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
        },
      ),
    );
  }

  Widget _guidanceSourceBuilder(
    Widget Function(BuildContext, NavigationGuidance) builder,
  ) {
    final listenable = widget.guidanceListenable;
    if (listenable != null) {
      return ValueListenableBuilder<NavigationGuidance>(
        valueListenable: listenable,
        builder: (context, guidance, _) => builder(context, guidance),
      );
    }
    final fixed = widget.guidance;
    if (fixed != null) {
      return Builder(builder: (context) => builder(context, fixed));
    }
    return ListenableBuilder(
      listenable: widget.engine,
      builder: (context, _) => builder(context, _nativeGuidance()),
    );
  }
}

/// A listenable that never notifies (fixed guidance).
class _Never implements Listenable {
  const _Never();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

/// Reports its child's size once it has been stable for a whole frame.
///
/// Layout during an animation or drag changes the size every frame; only
/// the settled size is reported, and only when it changed, so the parent is
/// not rebuilt per frame. No work happens on frames where the size did not
/// change.
class _SettledSize extends SingleChildRenderObjectWidget {
  const _SettledSize({required this.onSettled, required super.child});

  final ValueChanged<Size> onSettled;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSettledSize(onSettled);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSettledSize renderObject,
  ) {
    renderObject.onSettled = onSettled;
  }
}

class _RenderSettledSize extends RenderProxyBox {
  _RenderSettledSize(this.onSettled);

  ValueChanged<Size> onSettled;
  Size? _laidOut;
  Size? _reported;
  int _changes = 0;
  bool _armed = false;

  @override
  void performLayout() {
    super.performLayout();
    if (size != _laidOut) {
      _laidOut = size;
      _changes++;
      _arm();
    }
  }

  void _arm() {
    if (_armed) return;
    _armed = true;
    final generation = _changes;
    final scheduler = SchedulerBinding.instance;
    // From layout this runs at the end of the current frame; re-armed from a
    // post-frame check it needs one more frame, which nothing else may ask for.
    scheduler.ensureVisualUpdate();
    scheduler.addPostFrameCallback((_) {
      // Look again after the next frame: if layout changed the size in
      // between, it is still animating.
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => _confirm(generation),
      );
      SchedulerBinding.instance.scheduleFrame();
    });
  }

  void _confirm(int generation) {
    _armed = false;
    if (!attached) return;
    if (generation != _changes) {
      _arm();
      return;
    }
    if (hasSize && size != _reported) {
      _reported = size;
      onSettled(size);
    }
  }
}

class _SpeedCluster extends StatelessWidget {
  const _SpeedCluster({
    required this.speedKph,
    required this.limitKph,
    required this.language,
  });

  final double speedKph;
  final int? limitKph;
  final String language;

  @override
  Widget build(BuildContext context) {
    final speeding = limitKph != null && speedKph > limitKph!;
    final readout = CurrentSpeedReadout(
      speedKph: speedKph,
      speeding: speeding,
      language: language,
    );
    final sign = SpeedLimitSign(
      limitKph: limitKph,
      language: language,
      size: 56,
    );
    // On narrow phones the control rail needs the row; stack the roundel.
    if (MediaQuery.sizeOf(context).width < 360) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [sign, const SizedBox(height: 6), readout],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [readout, const SizedBox(width: 8), sign],
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
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: WaybiTextSize.caption,
              ),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: WaybiTextSize.title,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    this.onTap,
    this.toggled,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool? toggled;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: WaybiTouch.minTarget),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
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
                  fontSize: WaybiTextSize.caption,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Expanded(
      child: Semantics(
        toggled: toggled,
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
      ),
    );
  }
}

class _NavigationControlRail extends StatelessWidget {
  const _NavigationControlRail({
    required this.language,
    required this.following,
    required this.overviewMode,
    required this.northUp,
    required this.perspectiveTilted,
    required this.perspectiveAvailable,
    required this.onCompassToggle,
    required this.onRecenter,
    required this.onOverview,
    required this.onLayers,
    required this.onReport,
  });

  final bool following;
  final bool overviewMode;
  final bool northUp;
  final bool perspectiveTilted;
  final bool perspectiveAvailable;
  final String language;
  String _text(String en, String zh) => language == 'zh' ? zh : en;
  final VoidCallback onCompassToggle;
  final VoidCallback onRecenter;
  final VoidCallback onOverview;
  final VoidCallback onLayers;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final status = context.status;
    // Night variant: a dark rail does not glare over the dark map style.
    return Material(
      color: (dark ? WaybiColors.darkSurface : WaybiColors.lightSurface)
          .withValues(alpha: .97),
      elevation: 6,
      borderRadius: BorderRadius.circular(19),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RailButton(
            icon: northUp
                ? Icons.explore_rounded
                : perspectiveTilted
                ? Icons.threed_rotation
                : Icons.navigation_rounded,
            tooltip: northUp
                ? _text('North up · tap for heading-up', '北向俯视 · 点击车头朝上')
                : perspectiveTilted
                ? _text(
                    'Perspective follow · tap for north up',
                    '透视跟车 · 点击北向俯视',
                  )
                : !perspectiveAvailable
                ? _text('Heading up · tap for north up', '车头朝上 · 点击北向俯视')
                : _text(
                    'Heading-up flat · tap for perspective',
                    '车头朝上俯视 · 点击透视跟车',
                  ),
            onTap: onCompassToggle,
          ),
          const _RailDivider(),
          _RailButton(
            icon: overviewMode || !following
                ? Icons.my_location_rounded
                : Icons.alt_route_rounded,
            tooltip: overviewMode || !following
                ? _text('Re-center on my location', '回正导航')
                : _text('Route overview', '路线全览'),
            onTap: overviewMode || !following ? onRecenter : onOverview,
          ),
          const _RailDivider(),
          _RailButton(
            icon: Icons.layers_rounded,
            tooltip: _text('Map layers', '地图图层'),
            onTap: onLayers,
          ),
          const _RailDivider(),
          _RailButton(
            icon: Icons.add_alert_rounded,
            tooltip: _text('Report road issue', '报告路况'),
            onTap: onReport,
            iconColor: status.danger,
            backgroundColor: status.dangerContainer,
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
      Container(width: 1, height: 28, color: Theme.of(context).dividerColor);
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
      child: SizedBox.square(
        dimension: WaybiTouch.minTarget,
        child: IconButton(
          padding: EdgeInsets.zero,
          onPressed: onTap,
          tooltip: tooltip,
          iconSize: 22,
          icon: Icon(icon, color: iconColor ?? context.colors.onSurface),
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, color: scheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
