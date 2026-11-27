import 'package:flutter/material.dart';

import '../data/parking_repository.dart';
import '../theme/waybi_theme.dart';
import 'driving_motion.dart';
import 'waybi_format.dart';

/// Final-approach card shown inside the navigation deck.
///
/// While the car is moving it offers a single large "park at the nearest"
/// action; the full list of parking options appears once the car stops, so
/// choosing parking never needs fine-grained taps at speed.
class ArrivalExperiencePanel extends StatelessWidget {
  const ArrivalExperiencePanel({
    super.key,
    required this.language,
    required this.destinationTitle,
    required this.remainingMeters,
    required this.parkingPlaces,
    this.destinationAddress,
    required this.parkingLoading,
    required this.onParkingSelected,
    this.photoUrl,
    this.selectedParkingTitle,
    this.isMoving,
  });

  final String language;
  final String destinationTitle;
  final double remainingMeters;
  final String? destinationAddress;
  final String? photoUrl;
  final String? selectedParkingTitle;
  final List<ParkingPlace> parkingPlaces;
  final bool parkingLoading;
  final ValueChanged<ParkingPlace> onParkingSelected;

  /// Whether the vehicle is moving. When null, the nearest [DrivingMotion]
  /// (provided by the navigation overlay) decides.
  final bool? isMoving;

  static const _photoWidth = 92.0;
  static const _photoHeight = 112.0;

  String _text(String en, String zh) => language == 'zh' ? zh : en;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final moving = isMoving ?? DrivingMotion.of(context);
    final nearest = parkingPlaces.take(2).toList(growable: false);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final secondary = TextStyle(
      color: scheme.onSurfaceVariant,
      fontSize: WaybiTextSize.caption,
      fontWeight: FontWeight.w600,
    );
    final distance = formatDistance(remainingMeters, language);
    return Container(
      key: const Key('arrivalExperiencePanel'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withValues(alpha: .3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: photoUrl == null ? 72 : _photoWidth,
                height: _photoHeight,
                child: photoUrl == null
                    ? _ArrivalIcon(scheme: scheme)
                    : Image.network(
                        photoUrl!,
                        fit: BoxFit.cover,
                        cacheWidth: (_photoWidth * dpr).ceil(),
                        cacheHeight: (_photoHeight * dpr).ceil(),
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) => _ArrivalIcon(scheme: scheme),
                      ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.flag_rounded,
                            size: 17,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _text(
                                'Final approach · $distance',
                                '最后一段 · $distance',
                              ),
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: WaybiTextSize.caption,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        destinationTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: WaybiTextSize.bodyLarge,
                        ),
                      ),
                      if (destinationAddress != null &&
                          destinationAddress!.trim().isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Icon(
                              Icons.meeting_room_rounded,
                              size: 15,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                '${_text('Entrance', '入口')} · ${destinationAddress!.trim()}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: secondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _parking(context, scheme, secondary, moving, nearest),
          ),
        ],
      ),
    );
  }

  Widget _parking(
    BuildContext context,
    ColorScheme scheme,
    TextStyle secondary,
    bool moving,
    List<ParkingPlace> nearest,
  ) {
    if (selectedParkingTitle != null) {
      return Row(
        children: [
          Icon(Icons.local_parking_rounded, size: 18, color: scheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _text(
                'Parking · $selectedParkingTitle · continue on foot after parking',
                '停车点 · $selectedParkingTitle · 停车后继续步行',
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: secondary,
            ),
          ),
        ],
      );
    }
    if (parkingLoading) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _text('Finding parking near the entrance…', '正在查找终点附近停车…'),
              style: secondary,
            ),
          ),
        ],
      );
    }
    if (nearest.isEmpty) {
      return Text(
        _text(
          'Stay on the current route. Parking data is unavailable.',
          '继续沿当前路线行驶，暂未获取到附近停车信息。',
        ),
        style: secondary,
      );
    }
    String option(ParkingPlace parking) =>
        '${parking.name} · ${formatDistance(parking.distanceMeters, language)}';
    if (moving) {
      // One large, single-tap target while driving; the rest can wait.
      final first = nearest.first;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            key: const Key('arrivalParkNearest'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle: const TextStyle(
                fontSize: WaybiTextSize.bodyLarge,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: () => onParkingSelected(first),
            icon: const Icon(Icons.local_parking_rounded),
            label: Text(
              _text(
                'Park nearby · ${option(first)}',
                '就近停车 · ${option(first)}',
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _text(
              'More parking options appear when you stop.',
              '停车后可查看更多停车选项。',
            ),
            style: secondary,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _text(
            'Choose parking · the walk to the entrance follows',
            '选择停车点 · 之后接续步行到入口',
          ),
          style: secondary,
        ),
        for (final parking in nearest) ...[
          const SizedBox(height: 6),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(WaybiTouch.minTarget),
              alignment: AlignmentDirectional.centerStart,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              backgroundColor: scheme.surface,
            ),
            onPressed: () => onParkingSelected(parking),
            icon: const Icon(Icons.local_parking_rounded, size: 20),
            label: Text(
              option(parking),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

class _ArrivalIcon extends StatelessWidget {
  const _ArrivalIcon({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: scheme.primary.withValues(alpha: .13),
    child: Center(
      child: Icon(Icons.location_on_rounded, color: scheme.primary, size: 32),
    ),
  );
}
