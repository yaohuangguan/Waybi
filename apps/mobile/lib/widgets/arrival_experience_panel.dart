import 'package:flutter/material.dart';

import '../data/parking_repository.dart';
import '../theme/kiwi_lens_theme.dart';

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

  String _text(String en, String zh) => language == 'zh' ? zh : en;

  String get _distance {
    if (remainingMeters >= 1000) {
      return '${(remainingMeters / 1000).toStringAsFixed(1)} ${_text('km', '公里')}';
    }
    return '${remainingMeters.clamp(0, 999).round()} ${_text('m', '米')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nearest = parkingPlaces.take(2).toList(growable: false);
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (photoUrl != null)
            SizedBox(
              width: 92,
              height: 112,
              child: Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _ArrivalIcon(scheme: scheme),
              ),
            )
          else
            SizedBox(
              width: 72,
              height: 112,
              child: _ArrivalIcon(scheme: scheme),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.flag_rounded, size: 17, color: scheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _text(
                            'Final approach · $_distance',
                            '最后一段 · $_distance',
                          ),
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    destinationTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 7),
                  if (selectedParkingTitle != null)
                    Row(
                      children: [
                        Icon(
                          Icons.local_parking_rounded,
                          size: 16,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _text(
                              'Selected parking · $selectedParkingTitle',
                              '已选择停车点 · $selectedParkingTitle',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    )
                  else if (parkingLoading)
                    Row(
                      children: [
                        const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          _text(
                            'Finding parking near the entrance…',
                            '正在查找终点附近停车…',
                          ),
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    )
                  else if (nearest.isEmpty)
                    Text(
                      _text(
                        'Stay on the current route. Parking data is unavailable.',
                        '继续沿当前路线行驶，暂未获取到附近停车信息。',
                      ),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 10.5,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final parking in nearest)
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(
                              Icons.local_parking_rounded,
                              size: 15,
                            ),
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 135),
                              child: Text(
                                '${parking.name} · ${parking.distanceMeters < 1000 ? '${parking.distanceMeters.round()} ${_text('m', '米')}' : '${(parking.distanceMeters / 1000).toStringAsFixed(1)} ${_text('km', '公里')}'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onPressed: () => onParkingSelected(parking),
                          ),
                      ],
                    ),
                  if (!parkingLoading && nearest.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.directions_walk_rounded,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            selectedParkingTitle == null
                                ? _text(
                                    'Choose parking now · walking handoff appears when you arrive',
                                    '现在选择停车点 · 到达后会自动接续最后步行',
                                  )
                                : _text(
                                    'After parking · continue the final leg on foot',
                                    '停车后 · 继续最后一段步行',
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 9.8,
                              fontWeight: FontWeight.w600,
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
        ],
      ),
    );
  }
}

class _ArrivalIcon extends StatelessWidget {
  const _ArrivalIcon({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: KiwiLensColors.ocean.withValues(alpha: .13),
    child: Center(
      child: Icon(Icons.location_on_rounded, color: scheme.primary, size: 32),
    ),
  );
}
