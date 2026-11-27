import 'package:flutter/material.dart';

import '../domain/transit_lane.dart';
import '../theme/waybi_theme.dart';
import 'waybi_format.dart';

class NavigationTransitAlert extends StatelessWidget {
  const NavigationTransitAlert({
    super.key,
    required this.notice,
    this.language = 'en',
    this.compact = false,
  });
  final TransitLaneNotice notice;
  final String language;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final lane = notice.lane, zh = language == 'zh';
    final status = context.status;
    final ink = status.onWarningContainer;
    final title = lane.wholeRoad
        ? (zh ? '公交专用路段' : 'Bus-only road')
        : lane.label(language);
    final distance = notice.distanceMeters <= 5
        ? (zh ? '当前路段' : 'This section')
        : formatDistance(notice.distanceMeters, language);
    return Semantics(
      container: true,
      child: Container(
        key: const ValueKey('navigationTransitAlert'),
        padding: EdgeInsets.all(compact ? 10 : 12),
        decoration: BoxDecoration(
          color: status.warningContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.directions_bus_rounded, color: ink, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: ink,
                            fontSize: compact ? 15 : 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        distance,
                        style: TextStyle(
                          color: ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    lane.schedule.label(language),
                    style: TextStyle(
                      color: ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!compact)
                    Text(
                      notice.instruction(language),
                      style: TextStyle(color: ink, fontSize: 14),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
