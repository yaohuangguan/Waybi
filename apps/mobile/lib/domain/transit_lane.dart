import 'dart:math' as math;

import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'geo_math.dart';
import 'map_provider.dart';
import 'route_option.dart';

bool _timezoneReady = false;

class TransitSchedule {
  const TransitSchedule({
    required this.days,
    required this.windows,
    required this.known,
  });
  final List<int> days;
  final List<List<int>> windows;
  final bool known;

  factory TransitSchedule.fromJson(Map<String, dynamic> json) =>
      TransitSchedule(
        days: (json['days'] as List? ?? [])
            .whereType<num>()
            .map((v) => v.toInt())
            .toList(),
        windows: (json['windows'] as List? ?? [])
            .whereType<List>()
            .map((v) => v.whereType<num>().map((n) => n.toInt()).toList())
            .where((v) => v.length == 2)
            .toList(),
        known: json['known'] == true,
      );

  bool? activeAt(DateTime at) {
    if (!known || days.isEmpty || windows.isEmpty) return null;
    if (!_timezoneReady) {
      tzdata.initializeTimeZones();
      _timezoneReady = true;
    }
    final local = tz.TZDateTime.from(at, tz.getLocation('Pacific/Auckland'));
    final minute = local.hour * 60 + local.minute;
    return windows.any(
      (w) => w[0] < w[1]
          ? days.contains(local.weekday) && minute >= w[0] && minute < w[1]
          : days.contains(local.weekday) && minute >= w[0] ||
                days.contains(local.weekday == 1 ? 7 : local.weekday - 1) &&
                    minute < w[1],
    );
  }

  bool? activeDuring(DateTime from, DateTime until) {
    if (!known) return null;
    if (activeAt(from) == true || activeAt(until) == true) return true;
    for (
      var t = ((from.millisecondsSinceEpoch / 60000).ceil()) * 60000;
      t < until.millisecondsSinceEpoch;
      t += 60000
    ) {
      if (activeAt(DateTime.fromMillisecondsSinceEpoch(t, isUtc: true)) ==
          true) {
        return true;
      }
    }
    return false;
  }

  String label(String language, {bool speech = false}) {
    final zh = language == 'zh';
    if (!known) return zh ? '时段未确认，请查看路牌' : 'Hours unconfirmed · check signs';
    final everyDay = days.length == 7;
    final weekdays = days.join(',') == '1,2,3,4,5';
    final day = everyDay
        ? (zh ? '每天' : 'Every day')
        : weekdays
        ? (zh ? '周一至周五' : 'Monday to Friday')
        : days
              .map(
                (d) => zh
                    ? ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][d - 1]
                    : [
                        'Monday',
                        'Tuesday',
                        'Wednesday',
                        'Thursday',
                        'Friday',
                        'Saturday',
                        'Sunday',
                      ][d - 1],
              )
              .join(zh ? '、' : ', ');
    if (windows.length == 1 &&
        windows.first[0] == 0 &&
        windows.first[1] == 1440) {
      return everyDay
          ? (zh ? '全天生效 · 24/7' : 'Active 24 hours, every day')
          : '$day${zh ? '全天生效' : ', 24 hours'}';
    }
    String time(int m) => speech && zh
        ? '${m ~/ 60}点${m % 60 == 0 ? '' : '${m % 60}分'}'
        : '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    final hours = windows
        .map(
          (w) =>
              '${time(w[0])}${speech ? (zh ? '至' : ' to ') : '–'}${time(w[1])}',
        )
        .join(zh ? '、' : ', ');
    return '$day${zh ? ' ' : ', '}$hours';
  }
}

class TransitLane {
  const TransitLane({
    required this.id,
    required this.roadName,
    required this.kind,
    required this.schedule,
    required this.points,
    this.directionKnown = true,
    this.wholeRoad = false,
  });
  final String id, roadName, kind;
  final TransitSchedule schedule;
  final List<GeoPoint> points;
  final bool directionKnown, wholeRoad;

  factory TransitLane.fromJson(Map<String, dynamic> json) => TransitLane(
    id: json['id'] as String,
    roadName: json['roadName'] as String? ?? '',
    kind: json['kind'] as String,
    schedule: TransitSchedule.fromJson(
      json['schedule'] as Map<String, dynamic>,
    ),
    points: (json['coordinates'] as List)
        .whereType<List>()
        .where((v) => v.length >= 2)
        .map(
          (v) => GeoPoint((v[1] as num).toDouble(), (v[0] as num).toDouble()),
        )
        .toList(),
    directionKnown: json['directionKnown'] == true,
    wholeRoad: json['wholeRoad'] == true,
  );

  String label(String language) {
    final zh = language == 'zh';
    if (kind.startsWith('T2')) return zh ? 'T2 专用车道' : 'T2 transit lane';
    if (kind.startsWith('T3')) return zh ? 'T3 专用车道' : 'T3 transit lane';
    if (kind == 'Truck') return zh ? '货车专用车道' : 'Truck lane';
    return zh ? '公交车道' : 'Bus lane';
  }
}

class TransitLaneMatch {
  const TransitLaneMatch({
    required this.lane,
    required this.startMeters,
    required this.endMeters,
  });
  final TransitLane lane;
  final double startMeters, endMeters;
}

/// Build once per route, on a background isolate. GPS updates only scan the
/// resulting handful of overlaps, never the whole city's GIS geometry.
List<TransitLaneMatch> matchTransitLanes(
  RouteOption route,
  List<TransitLane> lanes,
) {
  if (route.mode != WaybiTravelMode.drive || route.points.length < 2) {
    return const [];
  }
  if (!route.points.any(
    (p) =>
        p.longitude >= 174.3 &&
        p.longitude <= 175.6 &&
        p.latitude >= -37.5 &&
        p.latitude <= -36.3,
  )) {
    return const [];
  }
  final cumulative = <double>[0], cells = <String, List<int>>{};
  for (var i = 1; i < route.points.length; i++) {
    final a = route.points[i - 1], b = route.points[i];
    cumulative.add(
      cumulative.last +
          distanceMeters(a.latitude, a.longitude, b.latitude, b.longitude),
    );
    final x1 = ((math.min(a.longitude, b.longitude) - .0004) * 1000).floor(),
        x2 = ((math.max(a.longitude, b.longitude) + .0004) * 1000).floor();
    final y1 = ((math.min(a.latitude, b.latitude) - .0003) * 1000).floor(),
        y2 = ((math.max(a.latitude, b.latitude) + .0003) * 1000).floor();
    if ((x2 - x1 + 1) * (y2 - y1 + 1) > 1000) continue;
    for (var x = x1; x <= x2; x++) {
      for (var y = y1; y <= y2; y++) {
        (cells['$x:$y'] ??= []).add(i);
      }
    }
  }
  final matches = <TransitLaneMatch>[];
  for (final lane in lanes) {
    var start = double.infinity, end = double.negativeInfinity;
    for (var i = 1; i < lane.points.length; i++) {
      final a = lane.points[i - 1], b = lane.points[i];
      final length = distanceMeters(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );
      final count = math.max(1, (length / 15).ceil());
      for (var j = 0; j <= count; j++) {
        final lon = a.longitude + (b.longitude - a.longitude) * j / count,
            lat = a.latitude + (b.latitude - a.latitude) * j / count;
        final scale = 111320 * math.cos(lat * math.pi / 180),
            lx = (b.longitude - a.longitude) * scale,
            ly = (b.latitude - a.latitude) * 111320;
        var nearestOffset = double.infinity;
        double? along;
        for (final index
            in cells['${(lon * 1000).floor()}:${(lat * 1000).floor()}'] ??
                const <int>[]) {
          final u = route.points[index - 1], v = route.points[index];
          final dx = (v.longitude - u.longitude) * scale,
              dy = (v.latitude - u.latitude) * 111320,
              square = dx * dx + dy * dy;
          if (square == 0 || length == 0) continue;
          final cosine =
              (lx * dx + ly * dy) / math.sqrt((lx * lx + ly * ly) * square);
          if (lane.directionKnown ? cosine < .82 : cosine.abs() < .82) continue;
          final px = (lon - u.longitude) * scale,
              py = (lat - u.latitude) * 111320,
              t = ((px * dx + py * dy) / square).clamp(0.0, 1.0);
          final offset = math.sqrt(
            math.pow(px - t * dx, 2) + math.pow(py - t * dy, 2),
          );
          if (offset > 22 || offset >= nearestOffset) continue;
          nearestOffset = offset;
          along =
              cumulative[index - 1] +
              t * (cumulative[index] - cumulative[index - 1]);
        }
        if (along != null) {
          start = math.min(start, along);
          end = math.max(end, along);
        }
      }
    }
    if (end - start >= 25) {
      matches.add(
        TransitLaneMatch(lane: lane, startMeters: start, endMeters: end),
      );
    }
  }
  return matches..sort((a, b) => a.startMeters.compareTo(b.startMeters));
}

List<TransitLaneMatch> transitRoadBlocks(
  RouteOption route,
  List<TransitLaneMatch> matches,
  DateTime now, {
  double progressMeters = 0,
}) {
  if (route.mode != WaybiTravelMode.drive) return const [];
  final names = route.steps
      .map((s) => s.roadName.toLowerCase())
      .where((s) => s.isNotEmpty)
      .toSet();
  return matches
      .where(
        (m) =>
            m.lane.wholeRoad &&
            m.lane.directionKnown &&
            (names.isEmpty || names.contains(m.lane.roadName.toLowerCase())) &&
            m.endMeters > progressMeters &&
            m.lane.schedule.activeDuring(
                  now.add(
                    Duration(
                      seconds:
                          (route.durationSeconds *
                                  ((m.startMeters - progressMeters) /
                                          math.max(1, route.distanceMeters))
                                      .clamp(0, 1))
                              .round(),
                    ),
                  ),
                  now.add(
                    Duration(
                      seconds:
                          (route.durationSeconds *
                                  ((m.endMeters - progressMeters) /
                                          math.max(1, route.distanceMeters))
                                      .clamp(0, 1))
                              .round(),
                    ),
                  ),
                ) ==
                true,
      )
      .toList();
}

class TransitLaneNotice {
  const TransitLaneNotice({
    required this.match,
    required this.distanceMeters,
    this.turningLeft = false,
  });
  final TransitLaneMatch match;
  final double distanceMeters;
  final bool turningLeft;
  TransitLane get lane => match.lane;
  String get alertKey =>
      '${lane.roadName.isEmpty ? lane.id : lane.roadName}:${lane.kind}:${lane.schedule.days}:${lane.schedule.windows}:${lane.directionKnown}';
  String instruction(String language) {
    final zh = language == 'zh';
    if (!lane.directionKnown || !lane.schedule.known) {
      return zh ? '请查看专用车道标志和生效时段' : 'Check lane signs and operating hours';
    }
    if (lane.wholeRoad) {
      return zh
          ? '此路段禁止普通汽车通行，请选择其他路线'
          : 'No access for ordinary cars · choose another route';
    }
    if (lane.kind.startsWith('T2') || lane.kind.startsWith('T3')) {
      return zh
          ? '请确认人数要求，否则保持普通车道'
          : 'Check occupancy requirements or stay in a general lane';
    }
    return turningLeft
        ? (zh
              ? '准备左转，请勿过早并入公交车道'
              : 'Turning left · avoid entering the bus lane too early')
        : (zh ? '请保持普通车道' : 'Stay in a general traffic lane');
  }

  String speech(String language) {
    final zh = language == 'zh';
    final road = lane.roadName.isEmpty
        ? ''
        : '${lane.roadName}${zh ? '，' : '. '}';
    final schedule = lane.schedule
        .label(language, speech: true)
        .replaceAll(' · 24/7', '');
    final stop = zh ? '。' : '. ';
    return '${zh ? '前方' : 'Ahead, '}$road${lane.label(language)}$stop$schedule$stop${instruction(language)}$stop';
  }
}
