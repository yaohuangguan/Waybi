import '../theme/kiwi_lens_theme.dart';

import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../drive/drive_engine.dart';
import '../drive/navigation_language.dart';
import 'kiwi_mascot.dart';
import 'road_event_timeline.dart';

const _ink = KiwiLensColors.darkOcean;
const _accent = KiwiLensColors.sky;

String navigationDistanceLabel(num? metres) {
  if (metres == null || !metres.isFinite) return '—';
  final safe = metres < 0 ? 0 : metres;
  if (safe >= 1000) return '${(safe / 1000).toStringAsFixed(1)} km';
  return '${safe.round()} m';
}

IconData _maneuverIcon(Maneuver? maneuver) {
  final name = maneuver?.name.toLowerCase() ?? '';
  if (name.contains('uturn')) return Icons.u_turn_left_rounded;
  if (name.contains('roundabout')) return Icons.roundabout_right_rounded;
  if (name.contains('right')) return Icons.turn_right_rounded;
  if (name.contains('left')) return Icons.turn_left_rounded;
  return Icons.straight_rounded;
}

class NavigationLane {
  const NavigationLane(this.symbol, this.recommended);
  final String symbol;
  final bool recommended;
}

/// Both providers feed the same Kiwi Lens HUD without manufacturing Google events.
class NavigationGuidance {
  const NavigationGuidance({
    required this.instruction,
    required this.maneuverIcon,
    this.stepMeters,
    this.remainingMeters,
    this.remainingSeconds,
    this.lanes = const [],
    this.lanesImage,
  });
  final String instruction;
  final IconData maneuverIcon;
  final num? stepMeters;
  final num? remainingMeters;
  final int? remainingSeconds;
  final List<NavigationLane> lanes;
  final ImageDescriptor? lanesImage;
}

class NavigationOverlay extends StatefulWidget {
  const NavigationOverlay({
    super.key,
    required this.engine,
    this.guidance,
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
  });

  final DriveEngine engine;
  final NavigationGuidance? guidance;
  final ValueChanged<double>? onTopInsetChanged;
  final ValueChanged<double>? onBottomInsetChanged;
  final String language;
  final String destinationTitle;
  final double? gpsAccuracy;
  final bool voiceEnabled;
  final bool lanesEnabled;
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
  final Widget? arrivalPanel;
  final bool offlineReady;
  final bool usingOfflineGuidance;
  final DateTime? offlineCachedAt;

  @override
  State<NavigationOverlay> createState() => _NavigationOverlayState();
}

class _NavigationOverlayState extends State<NavigationOverlay> {
  bool expanded = false;
  final _headerKey = GlobalKey();
  final _deckKey = GlobalKey();
  double? _reportedBottom;
  double? _reportedInset;
  double _headerHeight = 0;

  void _reportTopInset() {
    if (!mounted) return;
    final box = _headerKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final inset = box.size.height + 22 + MediaQuery.paddingOf(context).top;
    if (_reportedInset == null || (inset - _reportedInset!).abs() >= 1) {
      _reportedInset = inset;
      setState(() => _headerHeight = box.size.height);
      widget.onTopInsetChanged?.call(inset);
    }
  }

  void _reportBottomInset() {
    if (!mounted) return;
    final box = _deckKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final inset = box.size.height + 14;
    if (_reportedBottom == null || (inset - _reportedBottom!).abs() >= 1) {
      _reportedBottom = inset;
      widget.onBottomInsetChanged?.call(inset);
    }
  }

  double _sheetDrag = 0;
  ImageDescriptor? _laneDescriptor;
  Future<Image?>? _laneImage;
  String _text(String en, String zh) => widget.language == 'zh' ? zh : en;

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

  void _settleSheet(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final movement = _sheetDrag.abs() > 24 ? _sheetDrag : velocity / 12;
    if (movement.abs() > 24) setState(() => expanded = movement < 0);
    _sheetDrag = 0;
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportTopInset();
      _reportBottomInset();
    });
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final nav = widget.engine.navInfo;
    final step = nav?.currentStep;
    final guidance =
        widget.guidance ??
        NavigationGuidance(
          instruction: nav?.navState == NavState.rerouting
              ? _text('Updating route…', '正在重新规划路线…')
              : navigationInstruction(step, widget.language),
          lanesImage: step?.lanesImage,
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
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned(
              top: 10,
              left: 14,
              right: 14,
              child: Column(
                key: _headerKey,
                mainAxisSize: MainAxisSize.min,
                children: [
                  PointerInterceptor(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      alignment: Alignment.topCenter,
                      child: Container(
                        key: const ValueKey('navigationGuidanceHeader'),
                        padding: const EdgeInsets.all(16),
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
                              children: [
                                Icon(
                                  guidance.maneuverIcon,
                                  color: _accent,
                                  size: 38,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _distance(guidance.stepMeters),
                                        style: const TextStyle(
                                          color: _accent,
                                          fontSize: 25,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        guidance.instruction,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          height: 1.3,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      arrival,
                                      style: const TextStyle(
                                        color: _accent,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      _distance(guidance.remainingMeters),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (showLanes) ...[
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Divider(
                                  color: Colors.white24,
                                  height: 1,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    _text('USE LANE', '推荐车道'),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
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
                                                    selected: guidance
                                                        .lanes[index]
                                                        .recommended,
                                                    child: Container(
                                                      key: ValueKey(
                                                        'navigation-lane-$index',
                                                      ),
                                                      margin:
                                                          const EdgeInsets.only(
                                                            left: 5,
                                                          ),
                                                      constraints:
                                                          const BoxConstraints(
                                                            minWidth: 40,
                                                          ),
                                                      alignment:
                                                          Alignment.center,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 5,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            guidance
                                                                .lanes[index]
                                                                .recommended
                                                            ? _accent
                                                            : KiwiLensColors
                                                                  .darkSurface,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        guidance
                                                            .lanes[index]
                                                            .symbol,
                                                        style: TextStyle(
                                                          color:
                                                              guidance
                                                                  .lanes[index]
                                                                  .recommended
                                                              ? _ink
                                                              : Colors.white54,
                                                          fontSize: 25,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
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
                                              builder: (_, snapshot) =>
                                                  snapshot.data == null
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
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (camera != null && cameraDistance != null) ...[
                    const SizedBox(height: 8),
                    PointerInterceptor(
                      child: Container(
                        key: const ValueKey('navigationCameraAlert'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: _accent,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x26000000),
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.speed_rounded,
                              color: _ink,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_text('Camera', '摄像头')} · ${_distance(cameraDistance)}',
                                    style: const TextStyle(
                                      color: _ink,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    camera.location,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: KiwiLensColors.deepOcean,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (!expanded) ...[
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PointerInterceptor(
                          child: Container(
                            width: 84,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: _ink,
                              border: Border.all(
                                color: speeding
                                    ? const Color(0xFFFF6767)
                                    : Colors.white,
                                width: 3,
                              ),
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x33000000),
                                  blurRadius: 14,
                                ),
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
                                            fontWeight: FontWeight.w700,
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
                                  '${_text('LIMIT', '限速')} ${widget.engine.speedLimitKph ?? '—'}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
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
                            perspectiveAvailable: widget.perspectiveAvailable,
                            onCompassToggle: widget.onCompassToggle,
                            onRecenter: widget.onRecenter,
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
                    child: ConstrainedBox(
                      key: _deckKey,
                      constraints: BoxConstraints(
                        maxHeight: (constraints.maxHeight - _headerHeight - 170)
                            .clamp(100.0, constraints.maxHeight * .45),
                      ),
                      child: Material(
                        color: dark ? KiwiLensColors.darkOcean : scheme.surface,
                        elevation: 0,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(27),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              14,
                              3,
                              14,
                              bottomInset + 12,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onVerticalDragStart: (_) => _sheetDrag = 0,
                                  onVerticalDragUpdate: (details) =>
                                      _sheetDrag += details.delta.dy,
                                  onVerticalDragEnd: _settleSheet,
                                  child: InkWell(
                                    key: const Key('navigationSheetHandle'),
                                    onTap: () =>
                                        setState(() => expanded = !expanded),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      child: Container(
                                        width: 44,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: theme.dividerColor,
                                          borderRadius: BorderRadius.circular(
                                            5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    const KiwiMascot(size: 32),
                                    const SizedBox(width: 9),
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
                                    const SizedBox(width: 10),
                                    FilledButton.icon(
                                      onPressed: widget.onEnd,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: KiwiLensColors.danger,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 9,
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.stop_rounded,
                                        size: 18,
                                      ),
                                      label: Text(_text('End', '结束')),
                                    ),
                                  ],
                                ),
                                if (widget.arrivalPanel != null) ...[
                                  const SizedBox(height: 10),
                                  if (expanded)
                                    widget.arrivalPanel!
                                  else
                                    InkWell(
                                      key: const Key('arrivalSummary'),
                                      onTap: () =>
                                          setState(() => expanded = true),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.flag_rounded,
                                              size: 19,
                                              color: KiwiLensColors.ocean,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                _text(
                                                  'Almost there · arrival & parking',
                                                  '快到了 · 查看到达与停车信息',
                                                ),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            const Icon(
                                              Icons.expand_less_rounded,
                                              size: 18,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                                const SizedBox(height: 8),
                                const Divider(height: 1),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 9,
                                  ),
                                  child: Row(
                                    children: [
                                      _TripStat(
                                        label: _text(
                                          'Cameras on route',
                                          '沿途摄像头',
                                        ),
                                        value:
                                            '${widget.engine.routeCameraCount}',
                                      ),
                                      _TripStat(
                                        label: _text('Distance', '剩余距离'),
                                        value: _distance(
                                          guidance.remainingMeters,
                                        ),
                                      ),
                                      _TripStat(
                                        label: _text('Arrival', '预计到达'),
                                        value: arrival,
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1),
                                if (widget
                                    .engine
                                    .upcomingRoadEvents
                                    .isNotEmpty) ...[
                                  const SizedBox(height: KiwiLensSpacing.x2),
                                  RoadEventTimeline(
                                    events: widget.engine.upcomingRoadEvents,
                                    language: widget.language,
                                    dark: dark,
                                  ),
                                ],
                                if (expanded && widget.offlineReady) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: widget.usingOfflineGuidance
                                          ? KiwiLensColors.warning.withValues(
                                              alpha: .12,
                                            )
                                          : scheme.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(11),
                                      border: Border.all(
                                        color: theme.dividerColor,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          widget.usingOfflineGuidance
                                              ? Icons
                                                    .signal_wifi_connected_no_internet_4_rounded
                                              : Icons.offline_pin_rounded,
                                          size: 16,
                                          color: widget.usingOfflineGuidance
                                              ? KiwiLensColors.warning
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
                                              color: scheme.onSurfaceVariant,
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
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
                                          ? _text('Voice ✓', '语音 ✓')
                                          : _text('Voice off', '语音关闭'),
                                      onTap: widget.onVoiceToggle,
                                    ),
                                    const SizedBox(width: 6),
                                    _Chip(
                                      icon: Icons.alt_route_rounded,
                                      label: widget.lanesEnabled
                                          ? _text('Lanes ✓', '车道 ✓')
                                          : _text('Lanes off', '车道关闭'),
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
                                if (expanded) ...[
                                  const SizedBox(height: 15),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _text('Trip tools', '行程工具'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
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
                                        label: _text('Add a report', '添加上报'),
                                        onTap: widget.onReport,
                                      ),
                                      _ActionButton(
                                        icon: Icons.share_rounded,
                                        label: _text(
                                          'Share ETA snapshot',
                                          '分享预计到达',
                                        ),
                                        onTap: widget.onShare,
                                      ),
                                      _ActionButton(
                                        icon: Icons.search_rounded,
                                        label: _text(
                                          'Search along route',
                                          '沿途搜索',
                                        ),
                                        onTap: widget.onSearchAlongRoute,
                                      ),
                                      _ActionButton(
                                        icon: Icons.route_rounded,
                                        label: _text('Preview route', '路线总览'),
                                        onTap: widget.onOverview,
                                      ),
                                      _ActionButton(
                                        icon: Icons.list_alt_rounded,
                                        label: _text('Directions', '路线步骤'),
                                        onTap: widget.onDirections,
                                      ),
                                      _ActionButton(
                                        icon: Icons.settings_rounded,
                                        label: _text('Settings', '设置'),
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
              ),
            ),
          ],
        ),
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
                fontWeight: FontWeight.w600,
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
    required this.language,
    required this.following,
    required this.overviewMode,
    required this.northUp,
    required this.perspectiveTilted,
    required this.perspectiveAvailable,
    required this.onCompassToggle,
    required this.onRecenter,
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
  final VoidCallback onLayers;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .97),
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
            icon: overviewMode
                ? Icons.navigation_rounded
                : Icons.alt_route_rounded,
            tooltip: overviewMode
                ? _text('Follow my location', '进入跟车视角')
                : following
                ? _text('Route overview', '路线全览')
                : _text('Follow my location', '回到我的位置'),
            onTap: onRecenter,
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
            iconColor: KiwiLensColors.danger,
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
      Container(width: 1, height: 28, color: KiwiLensColors.lightBorder);
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
          icon: Icon(icon, color: iconColor ?? KiwiLensColors.darkOcean),
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
                      fontWeight: FontWeight.w600,
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
