import 'package:flutter/material.dart';

import '../domain/map_provider.dart';
import '../domain/route_option.dart';
import '../theme/kiwi_lens_theme.dart';

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
  final DateTime? geometryExpiresAt;
  final DateTime? lastCheckedAt;

  factory RouteWatchItem.fromJson(Map<String, dynamic> json) => RouteWatchItem(
    id: json['id']?.toString() ?? '',
    label: json['label']?.toString() ?? '',
    status: json['status']?.toString() ?? 'unknown',
    originName: json['originName']?.toString() ?? '',
    destinationName: json['destinationName']?.toString() ?? '',
    routeProvider: json['routeProvider']?.toString() ?? 'unknown',
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
    this.signedIn = false,
  });

  final Map<String, TripDestination> quickPlaces;
  final Map<String, RouteOption> quickRoutes;
  final List<TripDestination> recent;
  final List<TripHistoryItem> history;
  final Map<String, RouteWatchItem> routeWatches;
  final bool signedIn;
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
  final Set<String> _routeWatchBusy = <String>{};

  bool get _isChinese => widget.language == 'zh';
  String _text(String en, String zh) => _isChinese ? zh : en;

  @override
  void initState() {
    super.initState();
    _refresh();
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
      return KiwiLensColors.danger;
    }
    if (delay >= 180 || route.traffic.slow > 0) {
      return KiwiLensColors.warning;
    }
    return KiwiLensColors.success;
  }

  Color _watchColor(RouteWatchItem? watch) => switch (watch?.status) {
    'disrupted' => KiwiLensColors.danger,
    'warning' => KiwiLensColors.warning,
    'advisory' => KiwiLensColors.ocean,
    'healthy' => KiwiLensColors.success,
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

  String _watchSummary(RouteWatchItem? watch) {
    if (watch == null) {
      return _text(
        'Watch official NZTA incidents along this route',
        '持续监控这条路线上的 NZTA 官方道路事件',
      );
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
    RouteWatchItem? watch,
  ) {
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
                  _watchSummary(watch),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final snapshot = _snapshot;

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
                title: _text('Route Watch', '路线监控'),
                subtitle: _text('Plus preview', 'Plus 预览'),
              ),
              const SizedBox(height: 5),
              Text(
                _text(
                  'Kiwi Lens checks official NZTA road events against your saved route every 15 minutes without repeatedly buying a new Google route.',
                  'Kiwi Lens 每 15 分钟用 NZTA 官方道路事件检查收藏路线，不会为了监控反复购买新的 Google 路线。',
                ),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 11),
              if (!(snapshot?.signedIn ?? false))
                _EmptyCard(
                  icon: Icons.lock_outline_rounded,
                  text: _text(
                    'Sign in from My Kiwi Lens to save Route Watch to your account.',
                    '请先在“我的 Kiwi Lens”登录，再把路线监控保存到账号。',
                  ),
                )
              else if (!(snapshot!.quickPlaces.containsKey('Home') &&
                  snapshot.quickPlaces.containsKey('Work')))
                _EmptyCard(
                  icon: Icons.radar_rounded,
                  text: _text(
                    'Set both Home and Work first. Route Watch monitors the stable commute in both directions.',
                    '请先同时设置“家”和“公司”。路线监控会分别监控两个方向的固定通勤路线。',
                  ),
                )
              else ...[
                for (final label in const ['home-work', 'work-home'])
                  _routeWatchTile(context, label, snapshot.routeWatches[label]),
              ],
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
              else
                for (final item in snapshot!.history.take(10))
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
        ),
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
