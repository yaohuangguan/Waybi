import 'package:flutter/material.dart';

import '../domain/map_provider.dart';
import '../domain/route_option.dart';
import '../theme/waybi_theme.dart';

class TripDestination {
  const TripDestination({
    required this.name,
    required this.location,
    this.address = '',
  });

  final String name;
  final String address;
  final GeoPoint location;
}

class TripHistoryItem {
  const TripHistoryItem({
    required this.destination,
    required this.mode,
    required this.distanceMeters,
    required this.durationSeconds,
    this.createdAt,
  });

  final TripDestination destination;
  final String mode;
  final int distanceMeters;
  final int durationSeconds;
  final DateTime? createdAt;
}

class RouteWatchEvent {
  const RouteWatchEvent({
    required this.type,
    required this.severity,
    required this.description,
    required this.impact,
    this.roadName,
  });

  final String type;
  final String severity;
  final String description;
  final String impact;
  final String? roadName;

  factory RouteWatchEvent.fromJson(Map<String, dynamic> json) =>
      RouteWatchEvent(
        type: json['type']?.toString() ?? 'incident',
        severity: json['severity']?.toString() ?? 'advisory',
        description: json['description']?.toString() ?? '',
        impact: json['impact']?.toString() ?? '',
        roadName: json['roadName']?.toString(),
      );
}

class RouteWatchItem {
  const RouteWatchItem({
    required this.id,
    required this.label,
    required this.status,
    required this.events,
    this.originName = '',
    this.destinationName = '',
    this.routeProvider = 'unknown',
    this.baselineDurationSeconds,
    this.baselineDistanceMeters,
    this.geometryExpiresAt,
    this.lastCheckedAt,
  });

  final String id;
  final String label;
  final String status;
  final List<RouteWatchEvent> events;
  final String originName;
  final String destinationName;
  final String routeProvider;
  final int? baselineDurationSeconds;
  final int? baselineDistanceMeters;
  final DateTime? geometryExpiresAt;
  final DateTime? lastCheckedAt;

  factory RouteWatchItem.fromJson(Map<String, dynamic> json) => RouteWatchItem(
    id: json['id']?.toString() ?? '',
    label: json['label']?.toString() ?? '',
    status: json['status']?.toString() ?? 'unknown',
    originName: json['originName']?.toString() ?? '',
    destinationName: json['destinationName']?.toString() ?? '',
    routeProvider: json['routeProvider']?.toString() ?? 'unknown',
    baselineDurationSeconds: (json['baselineDurationSeconds'] as num?)?.round(),
    baselineDistanceMeters: (json['baselineDistanceMeters'] as num?)?.round(),
    geometryExpiresAt: DateTime.tryParse(
      json['geometryExpiresAt']?.toString() ?? '',
    ),
    events: (json['events'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RouteWatchEvent.fromJson)
        .toList(growable: false),
    lastCheckedAt: DateTime.tryParse(json['lastCheckedAt']?.toString() ?? ''),
  );
}

class TripsSnapshot {
  const TripsSnapshot({
    required this.quickPlaces,
    required this.quickRoutes,
    required this.recent,
    required this.history,
    this.routeWatches = const {},
    this.smartCommuteRoutes = const {},
    this.signedIn = false,
    this.isPlus = false,
  });

  final Map<String, TripDestination> quickPlaces;
  final Map<String, RouteOption> quickRoutes;
  final List<TripDestination> recent;
  final List<TripHistoryItem> history;
  final Map<String, RouteWatchItem> routeWatches;
  final Map<String, RouteOption> smartCommuteRoutes;
  final bool signedIn;
  final bool isPlus;
}

class TripsResult {
  const TripsResult.select(this.destination) : configureLabel = null;
  const TripsResult.configure(this.configureLabel) : destination = null;

  final TripDestination? destination;
  final String? configureLabel;
}

class TripsPage extends StatefulWidget {
  const TripsPage({
    super.key,
    required this.language,
    required this.loader,
    this.onRouteWatchChanged,
  });

  final String language;
  final Future<TripsSnapshot> Function() loader;
  final Future<void> Function(
    String label,
    RouteWatchItem? current,
    bool enabled,
  )?
  onRouteWatchChanged;

  @override
  State<TripsPage> createState() => _TripsPageState();
}

class _TripsPageState extends State<TripsPage> {
  TripsSnapshot? _snapshot;
  bool _loading = true;
  String? _error;
  final _historySearch = TextEditingController();
  String _historyMode = 'all';
  String _historyQuery = '';
  final Set<String> _routeWatchBusy = <String>{};

  bool get _isChinese => widget.language == 'zh';
  String _text(String en, String zh) => _isChinese ? zh : en;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _historySearch.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final snapshot = await widget.loader();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _text('Could not refresh trips right now.', '暂时无法刷新行程信息。');
      });
    }
  }

  String _duration(int seconds) {
    final minutes = (seconds / 60).ceil().clamp(1, 9999);
    if (minutes < 60) return _text('$minutes min', '$minutes 分钟');
    final hours = minutes ~/ 60;
    final remain = minutes % 60;
    if (remain == 0) return _text('${hours}h', '$hours 小时');
    return _text('${hours}h ${remain}m', '$hours 小时 $remain 分');
  }

  String _distance(int meters) {
    if (meters < 1000) return _text('$meters m', '$meters 米');
    final km = meters / 1000;
    final value = km < 10 ? km.toStringAsFixed(1) : km.round().toString();
    return _text('$value km', '$value 公里');
  }

  String _relativeTime(DateTime? time) {
    if (time == null) return '';
    final delta = DateTime.now().difference(time.toLocal());
    if (delta.inMinutes < 1) return _text('Just now', '刚刚');
    if (delta.inMinutes < 60) {
      return _text('${delta.inMinutes}m ago', '${delta.inMinutes} 分钟前');
    }
    if (delta.inHours < 24) {
      return _text('${delta.inHours}h ago', '${delta.inHours} 小时前');
    }
    if (delta.inDays < 7) {
      return _text('${delta.inDays}d ago', '${delta.inDays} 天前');
    }
    return '${time.toLocal().month}/${time.toLocal().day}';
  }

  IconData _modeIcon(String mode) => switch (mode) {
    'walk' || 'walking' => Icons.directions_walk_rounded,
    'bike' || 'bicycle' || 'cycling' => Icons.directions_bike_rounded,
    'transit' => Icons.directions_transit_rounded,
    _ => Icons.directions_car_filled_rounded,
  };

  Color _trafficColor(RouteOption route) {
    final delay = route.trafficDelaySeconds ?? 0;
    if (delay >= 600 || route.traffic.trafficJam > 0) {
      return WaybiColors.danger;
    }
    if (delay >= 180 || route.traffic.slow > 0) {
      return WaybiColors.warning;
    }
    return WaybiColors.success;
  }

  Color _watchColor(RouteWatchItem? watch) => switch (watch?.status) {
    'disrupted' => WaybiColors.danger,
    'warning' => WaybiColors.warning,
    'advisory' => WaybiColors.ocean,
    'healthy' => WaybiColors.success,
    _ => Theme.of(context).colorScheme.outline,
  };

  String _watchRouteLabel(String label) => switch (label) {
    'home-work' => _text('Home → Work', '家 → 公司'),
    'work-home' => _text('Work → Home', '公司 → 家'),
    _ => label,
  };

  String _watchStatus(RouteWatchItem? watch) {
    if (watch == null) return _text('Off', '未开启');
    return switch (watch.status) {
      'disrupted' => _text('Disrupted', '已中断'),
      'warning' => _text('Warning', '有警告'),
      'advisory' => _text('Advisory', '有提示'),
      'healthy' => _text('Clear', '正常'),
      _ => _text('Refresh', '需刷新'),
    };
  }

  String _watchSummary(RouteWatchItem? watch, {RouteOption? currentRoute}) {
    if (watch == null) {
      return _text(
        'Watch official NZTA incidents along this route',
        '持续监控这条路线上的 NZTA 官方道路事件',
      );
    }
    final baseline = watch.baselineDurationSeconds;
    if (currentRoute != null && baseline != null && baseline > 0) {
      final delta = currentRoute.durationSeconds - baseline;
      final deltaMinutes = (delta.abs() / 60).round();
      if (delta >= 300) {
        return _text(
          'Current ${_duration(currentRoute.durationSeconds)} · +$deltaMinutes min vs usual · leave $deltaMinutes min earlier',
          '当前 ${_duration(currentRoute.durationSeconds)} · 比平时多 $deltaMinutes 分钟 · 建议提前 $deltaMinutes 分钟出发',
        );
      }
      if (delta <= -180) {
        return _text(
          'Current ${_duration(currentRoute.durationSeconds)} · $deltaMinutes min faster than usual',
          '当前 ${_duration(currentRoute.durationSeconds)} · 比平时快 $deltaMinutes 分钟',
        );
      }
      if (watch.events.isEmpty) {
        return _text(
          'Current ${_duration(currentRoute.durationSeconds)} · close to your usual commute',
          '当前 ${_duration(currentRoute.durationSeconds)} · 接近平时通勤时间',
        );
      }
    }
    if (watch.status == 'unknown') {
      return _text(
        'Saved route geometry needs refreshing before monitoring can continue.',
        '已保存的路线需要刷新后才能继续监控。',
      );
    }
    if (watch.events.isEmpty) {
      final checked = _relativeTime(watch.lastCheckedAt);
      return checked.isEmpty
          ? _text('No official disruption detected', '未发现官方道路异常')
          : _text(
              'No official disruption · checked $checked',
              '未发现官方道路异常 · 检查于 $checked',
            );
    }
    final event = watch.events.first;
    final detail = [
      if (event.roadName?.isNotEmpty == true) event.roadName!,
      if (event.impact.isNotEmpty) event.impact,
      if (event.description.isNotEmpty) event.description,
    ].firstOrNull;
    final suffix = watch.events.length > 1
        ? _text(
            ' +${watch.events.length - 1} more',
            ' +另外 ${watch.events.length - 1} 项',
          )
        : '';
    return '${detail ?? _text('Road event detected', '检测到道路事件')}$suffix';
  }

  Future<void> _toggleRouteWatch(
    String label,
    RouteWatchItem? current,
    bool enabled,
  ) async {
    final callback = widget.onRouteWatchChanged;
    if (callback == null || _routeWatchBusy.contains(label)) return;
    setState(() {
      _routeWatchBusy.add(label);
      _error = null;
    });
    try {
      await callback(label, current, enabled);
      await _refresh();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error'.replaceFirst('Bad state: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _routeWatchBusy.remove(label));
    }
  }

  Future<void> _showRouteWatchDetails(
    String label,
    RouteWatchItem watch,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        final color = _watchColor(watch);
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.radar_rounded, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_watchRouteLabel(label)} · ${_watchStatus(watch)}',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                watch.lastCheckedAt == null
                    ? _text('Waiting for the first check', '等待首次检查')
                    : _text(
                        'Checked ${_relativeTime(watch.lastCheckedAt)}',
                        '检查于 ${_relativeTime(watch.lastCheckedAt)}',
                      ),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 16),
              if (watch.events.isEmpty)
                Text(
                  _text(
                    'No active NZTA road disruption is currently matched to this route.',
                    '当前没有 NZTA 官方道路异常与这条路线匹配。',
                  ),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                )
              else
                for (final event in watch.events) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 9),
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.roadName?.isNotEmpty == true
                              ? event.roadName!
                              : _text('Road event', '道路事件'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        if (event.impact.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            event.impact,
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (event.description.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            event.description,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
            ],
          ),
        );
      },
    );
  }

  Widget _routeWatchTile(
    BuildContext context,
    String label,
    RouteWatchItem? watch, {
    RouteOption? currentRoute,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = _watchColor(watch);
    final busy = _routeWatchBusy.contains(label);
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(11),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Icon(Icons.radar_rounded, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _watchRouteLabel(label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _watchStatus(watch),
                      style: TextStyle(
                        color: color,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _watchSummary(watch, currentRoute: currentRoute),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11.5,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (watch?.status == 'unknown')
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: _text('Refresh saved route', '刷新已保存路线'),
              onPressed: busy
                  ? null
                  : () => _toggleRouteWatch(label, watch, true),
              icon: const Icon(Icons.refresh_rounded, size: 20),
            )
          else if (watch != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: _text('Route Watch details', '路线监控详情'),
              onPressed: () => _showRouteWatchDetails(label, watch),
              icon: const Icon(Icons.info_outline_rounded, size: 20),
            ),
          Switch.adaptive(
            value: watch != null,
            onChanged: busy
                ? null
                : (value) => _toggleRouteWatch(label, watch, value),
          ),
        ],
      ),
    );
  }

  Widget _quickCard(
    BuildContext context,
    String label,
    TripDestination? place,
    RouteOption? route,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final configured = place != null;
    final color = route == null ? scheme.primary : _trafficColor(route);
    return Expanded(
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (place != null) {
              Navigator.of(context).pop(TripsResult.select(place));
            } else {
              Navigator.of(context).pop(TripsResult.configure(label));
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        label == 'Home'
                            ? Icons.home_rounded
                            : Icons.work_rounded,
                        color: scheme.primary,
                        size: 20,
                      ),
                    ),
                    const Spacer(),
                    if (route != null)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _text(label, label == 'Home' ? '家' : '公司'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                if (!configured)
                  Text(
                    _text('Set location', '设置地点'),
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else if (route == null)
                  Text(
                    _text('Tap to go', '点击出发'),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  )
                else ...[
                  Text(
                    _duration(route.durationSeconds),
                    style: const TextStyle(
                      fontSize: 22,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _distance(route.distanceMeters),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tripIntelligenceCard(TripsSnapshot snapshot) {
    final scheme = Theme.of(context).colorScheme;
    if (!snapshot.isPlus) {
      return _EmptyCard(
        icon: Icons.insights_rounded,
        text: _text(
          'Plus unlocks 30-day trip trends, distance, travel time and your most frequent destination.',
          'Plus 可解锁近 30 天行程趋势、距离、出行时间和最常去目的地。',
        ),
      );
    }

    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final recent = snapshot.history
        .where(
          (item) => item.createdAt != null && item.createdAt!.isAfter(cutoff),
        )
        .toList(growable: false);
    if (recent.isEmpty) {
      return _EmptyCard(
        icon: Icons.insights_rounded,
        text: _text(
          'Finish a few trips and your 30-day intelligence will appear here.',
          '完成几次行程后，这里会生成近 30 天的出行洞察。',
        ),
      );
    }

    final totalDistance = recent.fold<int>(
      0,
      (sum, item) => sum + item.distanceMeters,
    );
    final totalSeconds = recent.fold<int>(
      0,
      (sum, item) => sum + item.durationSeconds,
    );
    final counts = <String, int>{};
    for (final item in recent) {
      final name = item.destination.name.trim();
      if (name.isNotEmpty) counts[name] = (counts[name] ?? 0) + 1;
    }
    final favorite = counts.entries.isEmpty
        ? null
        : (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
              .first;
    final distanceKm = totalDistance / 1000;
    final hours = totalSeconds / 3600;
    final averageMinutes = (totalSeconds / recent.length / 60).round();
    final weekdayCounts = <int, int>{};
    var morningTrips = 0;
    var eveningTrips = 0;
    var otherTrips = 0;
    TripHistoryItem? longest;
    for (final item in recent) {
      final created = item.createdAt!.toLocal();
      weekdayCounts[created.weekday] =
          (weekdayCounts[created.weekday] ?? 0) + 1;
      if (created.hour >= 6 && created.hour < 10) {
        morningTrips++;
      } else if (created.hour >= 15 && created.hour < 19) {
        eveningTrips++;
      } else {
        otherTrips++;
      }
      if (longest == null || item.durationSeconds > longest.durationSeconds) {
        longest = item;
      }
    }
    final busiestWeekday = weekdayCounts.entries.isEmpty
        ? null
        : (weekdayCounts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first;
    const weekdaysEn = <int, String>{
      DateTime.monday: 'Mon',
      DateTime.tuesday: 'Tue',
      DateTime.wednesday: 'Wed',
      DateTime.thursday: 'Thu',
      DateTime.friday: 'Fri',
      DateTime.saturday: 'Sat',
      DateTime.sunday: 'Sun',
    };
    const weekdaysZh = <int, String>{
      DateTime.monday: '周一',
      DateTime.tuesday: '周二',
      DateTime.wednesday: '周三',
      DateTime.thursday: '周四',
      DateTime.friday: '周五',
      DateTime.saturday: '周六',
      DateTime.sunday: '周日',
    };
    final peakLabel = morningTrips >= eveningTrips && morningTrips >= otherTrips
        ? _text('Morning peak', '早高峰')
        : eveningTrips >= otherTrips
        ? _text('Evening peak', '晚高峰')
        : _text('Mixed times', '时段分散');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TripInsightStat(
                label: _text('Trips', '行程'),
                value: '${recent.length}',
              ),
              _TripInsightStat(
                label: _text('Distance', '距离'),
                value:
                    '${distanceKm.toStringAsFixed(distanceKm < 100 ? 1 : 0)} km',
              ),
              _TripInsightStat(
                label: _text('Travel time', '出行时间'),
                value: '${hours.toStringAsFixed(hours < 10 ? 1 : 0)} h',
              ),
            ],
          ),
          if (favorite != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: .45),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                children: [
                  Icon(Icons.star_rounded, size: 17, color: scheme.primary),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _text(
                        'Most visited · ${favorite.key} · ${favorite.value} trips',
                        '最常去 · ${favorite.key} · ${favorite.value} 次',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _TripPatternChip(
                icon: Icons.timelapse_rounded,
                label: _text('Avg', '平均'),
                value: _text('$averageMinutes min', '$averageMinutes 分钟'),
              ),
              if (busiestWeekday != null)
                _TripPatternChip(
                  icon: Icons.calendar_today_rounded,
                  label: _text('Busiest', '最多'),
                  value: _isChinese
                      ? weekdaysZh[busiestWeekday.key]!
                      : weekdaysEn[busiestWeekday.key]!,
                ),
              _TripPatternChip(
                icon: Icons.schedule_rounded,
                label: _text('Pattern', '时段'),
                value: peakLabel,
              ),
              if (longest != null)
                _TripPatternChip(
                  icon: Icons.route_rounded,
                  label: _text('Longest', '最长'),
                  value: _duration(longest.durationSeconds),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _commuteSetup(TripsSnapshot snapshot) {
    final saved = [
      'Home',
      'Work',
    ].where(snapshot.quickPlaces.containsKey).length;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _text('Set up your commute · $saved/2', '设置你的通勤 · $saved/2'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            _text(
              'Save Home and Work to watch both directions before you leave.',
              '保存家和公司，出发前就能了解两个方向的路况。',
            ),
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final label in const ['Home', 'Work'])
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: ValueKey('commute-setup-$label'),
                  onPressed: () =>
                      Navigator.of(context).pop(TripsResult.configure(label)),
                  icon: Icon(
                    snapshot.quickPlaces.containsKey(label)
                        ? Icons.check_circle_outline_rounded
                        : label == 'Home'
                        ? Icons.home_outlined
                        : Icons.work_outline_rounded,
                    size: 19,
                  ),
                  label: Text(
                    snapshot.quickPlaces.containsKey(label)
                        ? _text(
                            '$label saved · edit',
                            '${label == 'Home' ? '家' : '公司'}已保存 · 修改',
                          )
                        : _text(
                            'Set $label',
                            '设置${label == 'Home' ? '家' : '公司'}',
                          ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<TripHistoryItem> _filteredHistory(TripsSnapshot? snapshot) {
    final query = _historyQuery.trim().toLowerCase();
    return (snapshot?.history ?? const <TripHistoryItem>[])
        .where((item) {
          final mode = switch (item.mode) {
            'walk' || 'walking' => 'walk',
            'bike' || 'bicycle' || 'cycling' => 'bike',
            'transit' => 'transit',
            _ => 'drive',
          };
          return (_historyMode == 'all' || mode == _historyMode) &&
              (query.isEmpty ||
                  '${item.destination.name} ${item.destination.address}'
                      .toLowerCase()
                      .contains(query));
        })
        .toList(growable: false);
  }

  Widget _historyFilters() => Column(
    children: [
      TextField(
        key: const ValueKey('trip-history-search'),
        controller: _historySearch,
        textInputAction: TextInputAction.search,
        onChanged: (value) => setState(() => _historyQuery = value),
        decoration: InputDecoration(
          hintText: _text('Find a destination in your trips', '在行程中查找目的地'),
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _historyQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: _text('Clear search', '清空搜索'),
                  onPressed: () {
                    _historySearch.clear();
                    setState(() => _historyQuery = '');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
      ),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final entry in {
              'all': _text('All', '全部'),
              'drive': _text('Drive', '驾车'),
              'walk': _text('Walk', '步行'),
              'bike': _text('Cycle', '骑行'),
              'transit': _text('Transit', '公共交通'),
            }.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  key: ValueKey('trip-mode-${entry.key}'),
                  label: Text(entry.value),
                  selected: _historyMode == entry.key,
                  onSelected: (_) => setState(() => _historyMode = entry.key),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final snapshot = _snapshot;
    final filteredHistory = _filteredHistory(snapshot);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        title: Text(
          _text('Trips', '行程'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: _text('Refresh', '刷新'),
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Text(
              _text('Leave faster', '更快出发'),
              style: const TextStyle(
                fontSize: 27,
                height: 1.05,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _text(
                'Live commute times, recent destinations and your latest trips.',
                '实时通勤、最近目的地和最近行程都放在这里。',
              ),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            if (_loading && snapshot == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _quickCard(
                      context,
                      'Home',
                      snapshot?.quickPlaces['Home'],
                      snapshot?.quickRoutes['Home'],
                    ),
                    const SizedBox(width: 10),
                    _quickCard(
                      context,
                      'Work',
                      snapshot?.quickPlaces['Work'],
                      snapshot?.quickRoutes['Work'],
                    ),
                  ],
                ),
              ),
              if (_loading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: scheme.error, fontSize: 12),
                ),
              ],
              const SizedBox(height: 24),
              _SectionTitle(
                title: _text('Smart Commute', '智能通勤'),
                subtitle: snapshot?.isPlus == true
                    ? 'Plus'
                    : _text('Plus locked', 'Plus 专属'),
              ),
              const SizedBox(height: 5),
              Text(
                _text(
                  'Waybi compares today’s live Home ↔ Work time with your saved baseline and keeps watching official NZTA road disruptions in the background.',
                  'Waybi 会把今天家 ↔ 公司的实时通勤与平时基准对比，并持续后台监控 NZTA 官方道路异常。',
                ),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 11),
              if (!(snapshot?.isPlus ?? false))
                _EmptyCard(
                  icon: Icons.workspace_premium_rounded,
                  text: _text(
                    'Plus unlocks live commute-vs-usual timing, leave-earlier advice and background Route Watch.',
                    'Plus 可解锁“当前 vs 平时”通勤对比、提前出发建议和后台路线监控。',
                  ),
                )
              else if (!(snapshot?.signedIn ?? false))
                _EmptyCard(
                  icon: Icons.lock_outline_rounded,
                  text: _text(
                    'Sign in from My Waybi to save Smart Commute to your account.',
                    '请先在“我的 Waybi”登录，再把智能通勤保存到账号。',
                  ),
                )
              else if (!(snapshot!.quickPlaces.containsKey('Home') &&
                  snapshot.quickPlaces.containsKey('Work')))
                _commuteSetup(snapshot)
              else ...[
                for (final label in const ['home-work', 'work-home'])
                  _routeWatchTile(
                    context,
                    label,
                    snapshot.routeWatches[label],
                    currentRoute: snapshot.smartCommuteRoutes[label],
                  ),
              ],
              const SizedBox(height: 24),
              _SectionTitle(
                title: _text('Trip Intelligence', '行程洞察'),
                subtitle: snapshot?.isPlus == true
                    ? 'Plus · 30 days'
                    : _text('Plus locked', 'Plus 专属'),
              ),
              const SizedBox(height: 10),
              if (snapshot != null) _tripIntelligenceCard(snapshot),
              const SizedBox(height: 24),
              _SectionTitle(
                title: _text('Recent destinations', '最近目的地'),
                subtitle: _text('Continue with one tap', '一键继续出发'),
              ),
              const SizedBox(height: 10),
              if (snapshot?.recent.isEmpty ?? true)
                _EmptyCard(
                  icon: Icons.history_rounded,
                  text: _text(
                    'Places you navigate to will appear here.',
                    '你导航过的地点会自动出现在这里。',
                  ),
                )
              else
                for (final place in snapshot!.recent.take(6))
                  _DestinationTile(
                    place: place,
                    onTap: () =>
                        Navigator.of(context).pop(TripsResult.select(place)),
                  ),
              const SizedBox(height: 22),
              _SectionTitle(
                title: _text('Trip history', '行程记录'),
                subtitle: _text('Your latest completed routes', '最近完成的路线'),
              ),
              const SizedBox(height: 10),
              if (snapshot?.history.isEmpty ?? true)
                _EmptyCard(
                  icon: Icons.route_rounded,
                  text: _text(
                    'Finished trips will build your travel history.',
                    '完成导航后，这里会逐步形成你的出行记录。',
                  ),
                )
              else ...[
                _historyFilters(),
                const SizedBox(height: 10),
                Text(
                  _text(
                    '${filteredHistory.length} trips',
                    '${filteredHistory.length} 段行程',
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                if (filteredHistory.isEmpty)
                  _EmptyCard(
                    icon: Icons.search_off_rounded,
                    text: _text(
                      'No matching trips. Try another destination or travel mode.',
                      '没有找到匹配的行程，试试其他目的地或出行方式。',
                    ),
                  ),
                for (final item in filteredHistory)
                  _HistoryTile(
                    item: item,
                    modeIcon: _modeIcon(item.mode),
                    duration: _duration(item.durationSeconds),
                    distance: _distance(item.distanceMeters),
                    relativeTime: _relativeTime(item.createdAt),
                    onTap: () =>
                        Navigator.of(context)
                            .pop(TripsResult.select(item.destination)),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _TripInsightStat extends StatelessWidget {
  const _TripInsightStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TripPatternChip extends StatelessWidget {
  const _TripPatternChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .58),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 5),
          Text(
            '$label · $value',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          subtitle,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5),
        ),
      ],
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({required this.place, required this.onTap});

  final TripDestination place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Icon(Icons.history_rounded, color: scheme.primary),
        ),
        title: Text(
          place.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: place.address.isEmpty
            ? null
            : Text(place.address, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.arrow_forward_rounded, size: 18),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.item,
    required this.modeIcon,
    required this.duration,
    required this.distance,
    required this.relativeTime,
    required this.onTap,
  });

  final TripHistoryItem item;
  final IconData modeIcon;
  final String duration;
  final String distance;
  final String relativeTime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: scheme.secondaryContainer,
          child: Icon(modeIcon, color: scheme.onSecondaryContainer),
        ),
        title: Text(
          item.destination.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            duration,
            distance,
            if (relativeTime.isNotEmpty) relativeTime,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
