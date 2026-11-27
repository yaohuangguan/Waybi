import '../theme/waybi_theme.dart';

import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../domain/route_option.dart';
import 'hold_to_end_button.dart';
import 'waybi_format.dart';

const _ink = WaybiInk.surface;
const _accent = WaybiInk.accent;

String _duration(int seconds, String language) {
  final zh = language == 'zh';
  final duration = Duration(seconds: seconds);
  if (duration.inHours >= 1) {
    final minutes = duration.inMinutes.remainder(60);
    if (zh) {
      return minutes == 0
          ? '${duration.inHours} 小时'
          : '${duration.inHours} 小时 $minutes 分钟';
    }
    return minutes == 0
        ? '${duration.inHours} hr'
        : '${duration.inHours} hr $minutes min';
  }
  final minutes = duration.inMinutes.clamp(1, 999);
  return zh ? '$minutes 分钟' : '$minutes min';
}

class TransitTripOverlay extends StatelessWidget {
  const TransitTripOverlay({
    super.key,
    required this.destinationTitle,
    required this.route,
    required this.gpsAccuracy,
    required this.onEnd,
    required this.onRecenter,
    this.language,
  });

  final String destinationTitle;
  final RouteOption route;
  final double? gpsAccuracy;

  /// Called after the rider holds "End trip" (or confirms it with a screen
  /// reader); a short tap never ends the trip.
  final VoidCallback onEnd;
  final VoidCallback onRecenter;

  /// `en` or `zh`; defaults to the app locale.
  final String? language;

  @override
  Widget build(BuildContext context) {
    final lang = waybiLanguageOf(context, language);
    String text(String en, String zh) => lang == 'zh' ? zh : en;
    final scheme = Theme.of(context).colorScheme;
    final gps = gpsAccuracy == null
        ? 'GPS —'
        : 'GPS ±${formatDistance(gpsAccuracy!, lang)}';
    final arrival = TimeOfDay.fromDateTime(
      DateTime.now().add(Duration(seconds: route.durationSeconds)),
    ).format(context);

    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          Positioned(
            top: 10,
            left: 14,
            right: 14,
            child: PointerInterceptor(
              child: Material(
                color: _ink,
                elevation: 12,
                borderRadius: BorderRadius.circular(22),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.directions_transit_rounded,
                        color: _accent,
                        size: 34,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              text('TRANSIT TRIP', '公交行程'),
                              style: const TextStyle(
                                color: _accent,
                                fontSize: WaybiTextSize.caption,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              destinationTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: WaybiInk.text,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onRecenter,
                        tooltip: text('Recenter', '回到当前位置'),
                        icon: const Icon(
                          Icons.my_location_rounded,
                          color: WaybiInk.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: PointerInterceptor(
              child: Material(
                color: scheme.surface,
                elevation: 18,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(27),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _duration(route.durationSeconds, lang),
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    text(
                                      '${formatDistance(route.distanceMeters, lang)} · arrive $arrival · $gps',
                                      '${formatDistance(route.distanceMeters, lang)} · 预计 $arrival 到达 · $gps',
                                    ),
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: WaybiTextSize.caption,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            HoldToEndButton(
                              key: const Key('transitEndButton'),
                              label: text('End trip', '结束行程'),
                              holdHint: text('Hold to end', '长按结束'),
                              confirmTitle: text(
                                'End this transit trip?',
                                '结束本次公交行程？',
                              ),
                              confirmAction: text('End trip', '结束行程'),
                              cancelAction: text('Keep going', '继续行程'),
                              onEnd: onEnd,
                            ),
                          ],
                        ),
                        if (route.transit.isNotEmpty) ...[
                          const Divider(height: 22),
                          // Legs size to their text so large text scales
                          // grow the cards instead of overflowing them.
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (
                                    var index = 0;
                                    index < route.transit.length;
                                    index++
                                  ) ...[
                                    if (index > 0)
                                      const Icon(Icons.chevron_right_rounded),
                                    Builder(
                                      builder: (context) {
                                        final leg = route.transit[index];
                                        return Container(
                                          width: 190,
                                          padding: const EdgeInsets.all(11),
                                          decoration: BoxDecoration(
                                            color: scheme.surfaceContainerHigh,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                [leg.lineName, leg.headsign]
                                                    .where((v) => v.isNotEmpty)
                                                    .join(' → '),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${leg.departureStop} → ${leg.arrivalStop}',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize:
                                                      WaybiTextSize.caption,
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
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
