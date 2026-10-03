import 'package:flutter/material.dart';

import '../domain/road_event.dart';
import '../theme/waybi_theme.dart';

class RoadEventTimeline extends StatelessWidget {
  const RoadEventTimeline({
    super.key,
    required this.events,
    this.maneuverLabel,
    this.language = 'en',
    this.dark = true,
  });

  final List<RoadEvent> events;
  final String? maneuverLabel;
  final String language;
  final bool dark;

  String _text(String en, String zh) => language == 'zh' ? zh : en;

  String _distance(RoadEvent event) {
    final metres = event.distanceAlongRoute ?? event.distanceFromDriver;
    if (metres == null) return '';
    if (metres >= 1000) {
      return '${(metres / 1000).toStringAsFixed(1)} ${_text('km', '公里')}';
    }
    return '${metres.round()} ${_text('m', '米')}';
  }

  String _label(RoadEvent event) => switch (event.type) {
    RoadEventType.safetyCamera => _text('Camera', '摄像头'),
    RoadEventType.speedLimitChange => _text('Speed change', '限速变化'),
    RoadEventType.temporarySpeedLimit => _text('Temp. limit', '临时限速'),
    RoadEventType.roadworks => _text('Roadworks', '道路施工'),
    RoadEventType.incident => _text('Incident', '事故'),
    RoadEventType.congestion => _text('Traffic', '拥堵'),
    RoadEventType.schoolZone => _text('School zone', '学校区域'),
    RoadEventType.sharpCurve => _text('Sharp curve', '急弯'),
    RoadEventType.laneMerge => _text('Merge', '车道汇入'),
    RoadEventType.laneEnd => _text('Lane ends', '车道结束'),
    RoadEventType.oneLaneBridge => _text('One-lane bridge', '单车道桥'),
    RoadEventType.flooding => _text('Flooding', '积水'),
    RoadEventType.slip => _text('Slip', '滑坡'),
    RoadEventType.strongWind => _text('Strong wind', '强风'),
    RoadEventType.lowVisibility => _text('Low visibility', '低能见度'),
    RoadEventType.ice =>
      event.observation == RoadEventObservation.inferred
          ? _text('Possible ice', '可能结冰')
          : _text('Ice warning', '结冰警告'),
    RoadEventType.roadClosure => _text('Road closed', '道路封闭'),
  };

  IconData _icon(RoadEventType type) => switch (type) {
    RoadEventType.safetyCamera => Icons.speed_rounded,
    RoadEventType.speedLimitChange ||
    RoadEventType.temporarySpeedLimit => Icons.signpost_rounded,
    RoadEventType.roadworks => Icons.construction_rounded,
    RoadEventType.incident ||
    RoadEventType.roadClosure => Icons.warning_amber_rounded,
    RoadEventType.congestion => Icons.traffic_rounded,
    RoadEventType.schoolZone => Icons.school_rounded,
    RoadEventType.sharpCurve => Icons.turn_sharp_left_rounded,
    RoadEventType.laneMerge ||
    RoadEventType.laneEnd => Icons.merge_type_rounded,
    RoadEventType.oneLaneBridge => Icons.linear_scale_rounded,
    RoadEventType.flooding => Icons.water_rounded,
    RoadEventType.slip => Icons.landscape_rounded,
    RoadEventType.strongWind => Icons.air_rounded,
    RoadEventType.lowVisibility => Icons.visibility_off_rounded,
    RoadEventType.ice => Icons.ac_unit_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final visible = events.take(4).toList(growable: false);
    if (visible.isEmpty && maneuverLabel == null) {
      return const SizedBox.shrink();
    }
    final foreground = dark ? WaybiColors.darkText : WaybiColors.lightText;
    final muted = dark
        ? WaybiColors.darkTextSecondary
        : WaybiColors.lightTextSecondary;
    final surface = dark
        ? WaybiColors.darkOcean.withValues(alpha: .94)
        : WaybiColors.lightSurface.withValues(alpha: .96);
    final items = <Widget>[
      _TimelineNode(
        icon: Icons.navigation_rounded,
        label: _text('Now', '当前'),
        detail: maneuverLabel ?? _text('Driving', '行驶中'),
        color: WaybiColors.sky,
        foreground: foreground,
        muted: muted,
      ),
      for (final event in visible)
        _TimelineNode(
          icon: _icon(event.type),
          label: _label(event),
          detail: _distance(event),
          color: event.severity.index >= RoadEventSeverity.warning.index
              ? WaybiColors.warning
              : event.type == RoadEventType.safetyCamera
              ? WaybiColors.teal
              : WaybiColors.coastal,
          foreground: foreground,
          muted: muted,
        ),
    ];

    return Semantics(
      label: _text('Upcoming road events', '前方道路事件'),
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(
          horizontal: WaybiSpacing.x3,
          vertical: WaybiSpacing.x2,
        ),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(WaybiRadius.panel),
          border: Border.all(
            color: dark ? WaybiColors.darkBorder : WaybiColors.lightBorder,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [WaybiColors.ocean, WaybiColors.teal],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: WaybiSpacing.x2),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var index = 0; index < items.length; index++) ...[
                      if (index > 0)
                        Container(
                          width: 24,
                          height: 2,
                          color: dark
                              ? WaybiColors.darkBorder
                              : WaybiColors.lightBorder,
                        ),
                      items[index],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineNode extends StatelessWidget {
  const _TimelineNode({
    required this.icon,
    required this.label,
    required this.detail,
    required this.color,
    required this.foreground,
    required this.muted,
  });

  final IconData icon;
  final String label;
  final String detail;
  final Color color;
  final Color foreground;
  final Color muted;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 60, maxWidth: 112),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 29,
          height: 29,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: foreground,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (detail.isNotEmpty)
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: muted, fontSize: 10),
          ),
      ],
    ),
  );
}
