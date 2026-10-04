import 'package:flutter/material.dart';

import '../drive/drive_engine.dart';
import '../drive/navigation_language.dart';
import '../theme/waybi_theme.dart';

class NavigationCameraNotice {
  const NavigationCameraNotice(this.road, this.metres);
  final String road;
  final double metres;
}

NavigationCameraNotice? upcomingNavigationCamera(DriveEngine engine) {
  if (engine.locationIssue != null) return null;
  final camera = engine.upcomingCamera;
  final distance = engine.upcomingCameraDistanceMeters;
  if (camera != null &&
      distance != null &&
      distance.isFinite &&
      distance >= 0 &&
      distance <= 1200) {
    return NavigationCameraNotice(camera.location, distance);
  }
  // Keep the same confirmed camera lifecycle used by spoken reminders.
  // Cameras merely visible in the trip timeline do not occupy the map.
  return null;
}

class NavigationCameraAlert extends StatelessWidget {
  const NavigationCameraAlert({
    super.key,
    required this.notice,
    this.language = 'en',
  });
  final NavigationCameraNotice notice;
  final String language;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('navigationCameraAlert'),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    decoration: BoxDecoration(
      color: const Color(0xFFD0F58A),
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
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: WaybiColors.darkOcean,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.radar_rounded,
            color: Color(0xFFD0F58A),
            size: 27,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                language == 'zh' ? '前方安全摄像头' : 'Safety camera ahead',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: WaybiColors.darkOcean,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              if (notice.road.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  notice.road,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF394A35),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          navigationMetres(notice.metres, language),
          style: const TextStyle(
            color: WaybiColors.darkOcean,
            fontSize: 23,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}
