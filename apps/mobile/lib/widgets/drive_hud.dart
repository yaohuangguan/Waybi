import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart'
    show SpeedAlertSeverity;
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../drive/camera_alert_lifecycle.dart';
import '../drive/drive_engine.dart';
import '../drive/navigation_language.dart';
import '../domain/map_layer_settings.dart';
import '../domain/navigation_lanes.dart';
import '../theme/waybi_theme.dart';
import 'hold_to_end_button.dart';
import 'road_event_timeline.dart';
import 'lane_arrow.dart';
import 'navigation_maneuver_icon.dart';
import 'speed_readout.dart';
import 'waybi_format.dart';

/// Just Drive / native-guidance HUD: glanceable speed, limit, camera and
/// remaining distance in the driving type scale, and a hold-to-end control.
class DriveHud extends StatelessWidget {
  const DriveHud({
    super.key,
    required this.engine,
    required this.onStop,
    this.onRecenter,
    this.following = true,
    this.language,
  });

  final DriveEngine engine;

  /// Called after the driver holds "End drive" (or confirms it with a
  /// screen reader). A short tap never ends the drive.
  final VoidCallback onStop;
  final VoidCallback? onRecenter;
  final bool following;

  /// `en` or `zh`; defaults to the app locale.
  final String? language;

  String _formatDistance(double? meters, String language) =>
      meters == null ? '—' : navigationMetres(meters, language);

  @override
  Widget build(BuildContext context) {
    final lang = waybiLanguageOf(context, language);
    String text(String en, String zh) => lang == 'zh' ? zh : en;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final type = context.driveType;
    final status = context.status;
    final nav = engine.navInfo;
    final step = nav?.currentStep;
    final camera = engine.upcomingCamera;
    final cameraDistance = engine.upcomingCameraDistanceMeters;
    final passedCamera = engine.passedCamera;
    final intelligenceLabel = switch (engine.roadIntelligenceStatus) {
      'live' ||
      'seed' => text('NZ safety camera alerts active', '新西兰安全摄像头提醒已开启'),
      'stale' => text('Camera data may be out of date', '摄像头数据可能已过期'),
      'unsupported' => text(
        'Road Intelligence unavailable here',
        '此地区暂不支持道路情报',
      ),
      _ => text('Camera data unavailable', '摄像头数据暂不可用'),
    };
    final speeding =
        engine.speedSeverity == SpeedAlertSeverity.minor ||
        engine.speedSeverity == SpeedAlertSeverity.major ||
        (engine.speedLimitKph != null &&
            engine.speedKph > engine.speedLimitKph!);
    final endButton = HoldToEndButton(
      key: const Key('driveEndButton'),
      label: text('End drive', '结束驾驶'),
      holdHint: text('Hold to end drive', '长按结束驾驶'),
      confirmTitle: text('End this drive?', '结束本次驾驶？'),
      confirmAction: text('End drive', '结束驾驶'),
      cancelAction: text('Keep driving', '继续驾驶'),
      icon: Icons.close_rounded,
      compact: true,
      onInk: true,
      onEnd: onStop,
    );

    // Glance text is already in the driving scale; very large system text
    // scales are capped so the HUD never covers the whole map.
    // Short phones get a lower cap so the HUD and the map both fit.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: MediaQuery.sizeOf(context).height < 640 ? 1.3 : 1.6,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          child: Column(
            children: [
              if (step == null)
                PointerInterceptor(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                    decoration: BoxDecoration(
                      color: WaybiInk.surface.withValues(alpha: .96),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.directions_car_filled_rounded,
                          color: WaybiInk.accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                engine.routed
                                    ? text('Navigation', '导航')
                                    : text('Just Drive', '自由驾驶'),
                                style: type.secondary.copyWith(
                                  color: WaybiInk.text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                intelligenceLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: WaybiInk.muted,
                                  fontSize: WaybiTextSize.caption,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!following && onRecenter != null)
                          IconButton(
                            tooltip: text('Return to my location', '回到当前位置'),
                            onPressed: onRecenter,
                            icon: const Icon(Icons.my_location_rounded),
                            color: WaybiInk.text,
                          ),
                        endButton,
                      ],
                    ),
                  ),
                ),
              if (step != null)
                PointerInterceptor(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                    decoration: BoxDecoration(
                      color: WaybiInk.surface.withValues(alpha: .96),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          navigationManeuverIcon(step.maneuver.name),
                          color: WaybiInk.accent,
                          size: 38,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatDistance(
                                  nav?.distanceToCurrentStepMeters?.toDouble(),
                                  lang,
                                ),
                                style: type.distance.copyWith(
                                  color: WaybiInk.accent,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                step.fullInstructions ??
                                    step.fullRoadName ??
                                    text('Continue', '继续行驶'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: type.instruction.copyWith(
                                  color: WaybiInk.text,
                                ),
                              ),
                              if (step.lanes?.isNotEmpty ?? false) ...[
                                const SizedBox(height: 9),
                                Wrap(
                                  spacing: 5,
                                  runSpacing: 5,
                                  children: step.lanes!.map((lane) {
                                    final recommended = lane.laneDirections.any(
                                      (direction) => direction.isRecommended,
                                    );
                                    final directions = laneDirections(
                                      lane.laneDirections.map(
                                        (d) => d.laneShape.name,
                                      ),
                                    );
                                    return Container(
                                      constraints: const BoxConstraints(
                                        minWidth: 34,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: recommended
                                            ? WaybiInk.accent
                                            : WaybiInk.raised,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: LaneArrow(
                                        directions: directions,
                                        size: 30,
                                        language: lang,
                                        color: recommended
                                            ? WaybiColors.midnightOcean
                                            : WaybiInk.muted,
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                        endButton,
                      ],
                    ),
                  ),
                ),
              if (passedCamera != null &&
                  engine.cameraAlertState.phase == CameraAlertPhase.passed)
                PointerInterceptor(
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: WaybiSpacing.x2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: WaybiSpacing.x4,
                      vertical: WaybiSpacing.x3,
                    ),
                    decoration: BoxDecoration(
                      color: status.success,
                      borderRadius: BorderRadius.circular(WaybiRadius.panel),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: status.onSuccess,
                        ),
                        const SizedBox(width: WaybiSpacing.x3),
                        Expanded(
                          child: Text(
                            text(
                              'Camera passed · ${passedCamera.location}',
                              '已通过摄像头 · ${passedCamera.location}',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: type.secondary.copyWith(
                              color: status.onSuccess,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (camera != null && cameraDistance != null)
                PointerInterceptor(
                  child: Container(
                    key: const ValueKey('driveCameraAlert'),
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: WaybiColors.sky,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 20,
                          color: Color(0x26000000),
                          offset: Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.speed_rounded,
                          color: WaybiColors.deepOcean,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${text('Safety camera', '摄像头')} · ${_formatDistance(cameraDistance, lang)}',
                                style: type.instruction.copyWith(
                                  color: WaybiColors.midnightOcean,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${CameraKindLabel.fromCamera(camera).localizedLabel(lang)} · ${camera.location}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: type.secondary.copyWith(
                                  color: WaybiColors.deepOcean,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const Spacer(),
              if (engine.upcomingRoadEvents.isNotEmpty && camera == null) ...[
                RoadEventTimeline(
                  events: engine.upcomingRoadEvents,
                  dark: dark,
                  language: lang,
                ),
                const SizedBox(height: WaybiSpacing.x2),
              ],
              PointerInterceptor(
                child: Container(
                  key: const ValueKey('driveMetrics'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: WaybiInk.surface.withValues(alpha: .96),
                    borderRadius: BorderRadius.circular(20),
                    border: speeding
                        ? Border.all(color: WaybiInk.danger, width: 2.5)
                        : null,
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(
                          child: CurrentSpeedReadout(
                            speedKph: engine.speedKph,
                            speeding: speeding,
                            language: lang,
                            framed: false,
                          ),
                        ),
                        SpeedLimitSign(
                          limitKph: engine.speedLimitKph,
                          language: lang,
                          size: 54,
                        ),
                        const _MetricDivider(),
                        _Metric(
                          label: text('Camera', '摄像头'),
                          value: cameraDistance == null
                              ? '—'
                              : _formatDistance(cameraDistance, lang),
                        ),
                        if (nav?.distanceToFinalDestinationMeters != null) ...[
                          const _MetricDivider(),
                          _Metric(
                            label: text('Remaining', '剩余'),
                            value: _formatDistance(
                              nav!.distanceToFinalDestinationMeters!.toDouble(),
                              lang,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    color: WaybiInk.border,
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final type = context.driveType;
    return Expanded(
      child: Semantics(
        label: '$label $value',
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: type.label.copyWith(color: WaybiInk.muted),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: type.value.copyWith(color: WaybiInk.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
