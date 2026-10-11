import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import '../domain/road_event.dart';
import '../theme/waybi_theme.dart';
import 'discover_memory.dart';
import 'trips_page.dart';

enum DiscoverActionKind { search, trips, destination, direction, roadEvent }

class DiscoverAction {
  const DiscoverAction._(
    this.kind, {
    this.destination,
    this.center,
    this.event,
  });
  static const newDestination = DiscoverAction._(DiscoverActionKind.search);
  static const trips = DiscoverAction._(DiscoverActionKind.trips);
  factory DiscoverAction.place(TripDestination place) =>
      DiscoverAction._(DiscoverActionKind.destination, destination: place);
  factory DiscoverAction.direction(GeoPoint center) =>
      DiscoverAction._(DiscoverActionKind.direction, center: center);
  factory DiscoverAction.road(RoadEvent event) =>
      DiscoverAction._(DiscoverActionKind.roadEvent, event: event);
  final DiscoverActionKind kind;
  final TripDestination? destination;
  final GeoPoint? center;
  final RoadEvent? event;
}

class DiscoverRoadSnapshot {
  const DiscoverRoadSnapshot({
    required this.events,
    required this.status,
    this.checkedAt,
    this.officialCoverage = const [],
  });
  final List<RoadEvent> events;
  final String status;
  final DateTime? checkedAt;
  final List<String> officialCoverage;
}

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({
    super.key,
    required this.language,
    required this.loader,
    this.roadLoader,
    this.origin,
  });
  final String language;
  final Future<TripsSnapshot> Function() loader;
  final Future<DiscoverRoadSnapshot> Function()? roadLoader;
  final GeoPoint? origin;
  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  TripsSnapshot? _snapshot;
  DiscoverRoadSnapshot? _roads;
  bool _loading = true, _roadsLoading = true, _historyError = false;
  int _request = 0;
  String _text(String en, String zh) => widget.language == 'zh' ? zh : en;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _roadsLoading = true;
      _historyError = false;
    });
    await Future.wait([_loadHistory(request), _loadRoads(request)]);
  }

  Future<void> _loadHistory(int request) async {
    try {
      final snapshot = await widget.loader();
      if (!mounted || request != _request) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _historyError = true;
        _loading = false;
      });
    }
  }

  Future<void> _loadRoads(int request) async {
    DiscoverRoadSnapshot result;
    try {
      result =
          await widget.roadLoader?.call() ??
          const DiscoverRoadSnapshot(events: [], status: 'not_loaded');
    } catch (_) {
      result = const DiscoverRoadSnapshot(events: [], status: 'unavailable');
    }
    if (!mounted || request != _request) return;
    setState(() {
      _roads = result;
      _roadsLoading = false;
    });
  }

  double _eventDistance(RoadEvent event) {
    final origin = widget.origin;
    if (origin == null) return double.infinity;
    final points = event.geometry.isEmpty ? [event.location] : event.geometry;
    return points
        .map(
          (p) => distanceMeters(
            origin.latitude,
            origin.longitude,
            p.latitude,
            p.longitude,
          ),
        )
        .reduce(math.min);
  }

  List<RoadEvent> get _nearbyEvents {
    final now = DateTime.now();
    final events = (_roads?.events ?? const <RoadEvent>[])
        .where(
          (event) =>
              event.type != RoadEventType.safetyCamera &&
              event.observation != RoadEventObservation.inferred &&
              event.isCurrent(now) &&
              _eventDistance(event) <= 30000,
        )
        .toList();
    events.sort((a, b) {
      final severity = b.severity.index.compareTo(a.severity.index);
      return severity != 0
          ? severity
          : _eventDistance(a).compareTo(_eventDistance(b));
    });
    return events;
  }

  String _eventTitle(RoadEvent event) => switch (event.type) {
    RoadEventType.roadClosure => _text('Road closed', '道路封闭'),
    RoadEventType.roadworks => _text('Roadworks', '道路施工'),
    RoadEventType.flooding => _text('Flooding', '积水 / 洪水'),
    RoadEventType.slip => _text('Slip / debris', '滑坡 / 道路杂物'),
    _ => _text('Road incident', '道路事件'),
  };
  String _lastVisited(DateTime? date) {
    if (date == null) return _text('Visited before', '曾经到访');
    final days = DateTime.now().difference(date).inDays;
    if (days <= 0) return _text('Visited today', '今天到访');
    if (days == 1) return _text('Visited yesterday', '昨天到访');
    return _text('Last visited $days days ago', '上次到访是 $days 天前');
  }

  void _choose(DiscoverAction action) => Navigator.of(context).pop(action);
  String _directionName(int sector) => switch (sector) {
    0 => _text('North', '北边'),
    1 => _text('East', '东边'),
    2 => _text('South', '南边'),
    _ => _text('West', '西边'),
  };
  Widget _roadCard() {
    final nearby = _nearbyEvents;
    final unavailable = _roads?.status == 'not_loaded' ||
      (_roads?.status == 'unavailable' && _roads?.checkedAt == null);
    final coverage = _roads?.officialCoverage ?? const <String>[];
    final publisher = coverage.contains('NZ')
        ? 'NZTA'
        : coverage.contains('AU-NSW')
        ? 'Transport for NSW'
        : null;
    final checked = _roads?.checkedAt;
    final age = checked == null
        ? null
        : DateTime.now().difference(checked).inMinutes.clamp(0, 999);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.add_road_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _text('Before you go', '出发前看一眼'),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (_roadsLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _text('Road updates within 30 km', '附近 30 公里的道路更新'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!_roadsLoading && unavailable) ...[
              const SizedBox(height: 10),
              Text(
                _text('Road updates are unavailable right now.', '暂时无法获取道路更新。'),
              ),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(_text('Try again', '重试')),
              ),
            ] else if (!_roadsLoading && widget.origin == null) ...[
              const SizedBox(height: 10),
              Text(
                _text(
                  'Choose a map area to see nearby road updates.',
                  '选择地图区域后查看附近路况。',
                ),
              ),
            ] else if (!_roadsLoading && nearby.isEmpty) ...[
              const SizedBox(height: 10),
              Text(_text('No published road events nearby.', '附近暂无已发布的道路事件。')),
            ],
            for (final event in nearby.take(3)) ...[
              const Divider(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: event.type == RoadEventType.roadClosure
                      ? const Color(0xffffe7e5)
                      : const Color(0xfffff0d7),
                  child: Icon(
                    event.type == RoadEventType.roadClosure
                        ? Icons.block_rounded
                        : Icons.construction_rounded,
                    color: event.type == RoadEventType.roadClosure
                        ? const Color(0xffb52e35)
                        : const Color(0xff946214),
                  ),
                ),
                title: Text(
                  event.roadName ?? _eventTitle(event),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${_eventTitle(event)} · ${(_eventDistance(event) / 1000).toStringAsFixed(1)} km',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _choose(DiscoverAction.road(event)),
              ),
            ],
            if (!_roadsLoading && !unavailable) ...[
              const SizedBox(height: 10),
              Text(
                _roads?.status == 'stale'
                    ? _text(
                        'Cached updates · refresh to check the latest',
                        '缓存路况 · 刷新以检查最新更新',
                      )
                    : _text(
                        publisher == null
                            ? 'Waybi driver reports · official coverage is not available here yet'
                            : '$publisher · Waybi driver reports',
                        publisher == null
                            ? 'Waybi 用户报告 · 此地区暂未接入官方路况'
                            : '$publisher · Waybi 用户报告',
                      ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (age != null)
                Text(
                  _text(
                    age == 0 ? 'Checked just now' : 'Checked $age min ago',
                    age == 0 ? '刚刚检查' : '$age 分钟前检查',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final history = _snapshot?.history ?? const <TripHistoryItem>[];
    final counts = visitedDirectionCounts(widget.origin, history);
    final sector = leastVisitedDirection(counts);
    final places = rediscoveryPlaces(history);
    return Scaffold(
      appBar: AppBar(title: Text(_text('Discover', '发现'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: theme.brightness == Brightness.dark
                      ? [const Color(0xff183a32), const Color(0xff294735)]
                      : [const Color(0xffedf4dd), const Color(0xfffaf4df)],
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          _text(
                            'Find your next little trip.',
                            '下一段小旅程，\n一起出发。',
                          ),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Image.asset(
                        'assets/characters/waybi.png',
                        package: 'waybi_friends',
                        width: 82,
                        height: 82,
                        semanticLabel: _text(
                          'Waybi the kiwi bird',
                          'Kiwi 鸟 Waybi',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _text(
                      'A new place, a familiar favourite, and a look at the road ahead.',
                      '去个新地方，重访喜欢的角落，也看看前方的路。',
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => _choose(DiscoverAction.newDestination),
                    icon: const Icon(Icons.search_rounded),
                    label: Text(_text('Choose somewhere new', '去个新地方')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                Text(
                  _loading
                      ? _text('Reading your journeys…', '正在读取旅程…')
                      : _text(
                          '${history.length} journeys · ${places.length} places',
                          '${history.length} 段旅程 · ${places.length} 个地点',
                        ),
                ),
                TextButton(
                  onPressed: () => _choose(DiscoverAction.trips),
                  child: Text(_text('View trips', '查看行程')),
                ),
              ],
            ),
            if (_historyError)
              Card(
                child: ListTile(
                  title: Text(
                    _text('Journey history could not load', '旅程记录加载失败'),
                  ),
                  trailing: TextButton(
                    onPressed: _load,
                    child: Text(_text('Retry', '重试')),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            _roadCard(),
            const SizedBox(height: 18),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text('A different direction', '换个方向看看'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        SizedBox(
                          width: 92,
                          height: 92,
                          child: CustomPaint(
                            painter: _DirectionPainter(
                              selected: sector,
                              color: theme.colorScheme.primary,
                              muted: theme.colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Text(
                            sector == null
                                ? _text(
                                    'Your next journey starts a new memory.',
                                    '下一段旅程，会带来新的回忆。',
                                  )
                                : _text(
                                    '${_directionName(sector)} has fewer places you have visited from here.',
                                    '从这里出发，你在${_directionName(sector)}到访过的区域较少。',
                                  ),
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: widget.origin == null
                          ? null
                          : () {
                              final origin = widget.origin!;
                              _choose(
                                DiscoverAction.direction(
                                  sector == null
                                      ? origin
                                      : directionSearchCenter(origin, sector),
                                ),
                              );
                            },
                      icon: const Icon(Icons.explore_outlined),
                      label: Text(
                        sector == null
                            ? _text('Find nearby places', '发现附近地点')
                            : _text(
                                'Explore ${_directionName(sector).toLowerCase()}',
                                '探索${_directionName(sector)}',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (places.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                _text('Worth another visit', '值得再去一次'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              for (final trip in places.take(3))
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: const CircleAvatar(
                      backgroundColor: WaybiColors.ice,
                      child: Icon(
                        Icons.landscape_rounded,
                        color: WaybiColors.deepTeal,
                      ),
                    ),
                    title: Text(
                      trip.destination.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(_lastVisited(trip.createdAt)),
                    trailing: const Icon(Icons.arrow_outward_rounded),
                    onTap: () =>
                        _choose(DiscoverAction.place(trip.destination)),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DirectionPainter extends CustomPainter {
  _DirectionPainter({
    required this.selected,
    required this.color,
    required this.muted,
  });
  final int? selected;
  final Color color, muted;
  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero), radius = size.shortestSide / 2 - 4;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    for (var sector = 0; sector < 4; sector++) {
      stroke.color = sector == selected ? color : muted;
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        -math.pi * 3 / 4 + sector * math.pi / 2,
        math.pi / 2 - .15,
        false,
        stroke,
      );
    }
    final arrow = Path()
      ..moveTo(centre.dx, centre.dy - 18)
      ..lineTo(centre.dx + 12, centre.dy + 12)
      ..lineTo(centre.dx, centre.dy + 6)
      ..lineTo(centre.dx - 12, centre.dy + 12)
      ..close();
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate((selected ?? 0) * math.pi / 2);
    canvas.translate(-centre.dx, -centre.dy);
    canvas.drawPath(arrow, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DirectionPainter old) =>
      old.selected != selected || old.color != color || old.muted != muted;
}
