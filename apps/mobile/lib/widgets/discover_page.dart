import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/map_provider.dart';
import '../theme/waybi_theme.dart';
import 'trips_page.dart';

enum DiscoverAction { newDestination, trips }

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({
    super.key,
    required this.language,
    required this.loader,
    this.origin,
  });

  final String language;
  final Future<TripsSnapshot> Function() loader;
  final GeoPoint? origin;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  TripsSnapshot? _snapshot;
  bool _loading = true;

  bool get _zh => widget.language == 'zh';
  String _text(String en, String zh) => _zh ? zh : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snapshot = await widget.loader();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<TripHistoryItem> get _leastRecentPlaces {
    final history = [...?_snapshot?.history]
      ..sort((a, b) {
        final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return at.compareTo(bt);
      });
    final seen = <String>{};
    return history
        .where((item) => seen.add(item.destination.name.toLowerCase()))
        .take(3)
        .toList(growable: false);
  }

  int get _uniqueDestinations {
    return _snapshot?.history
            .map((item) => item.destination.name.trim().toLowerCase())
            .where((name) => name.isNotEmpty)
            .toSet()
            .length ??
        0;
  }

  Map<int, int> get _directionCounts {
    final origin = widget.origin;
    if (origin == null) return const {};
    final counts = <int, int>{0: 0, 1: 0, 2: 0, 3: 0};
    final visitedCells = <String>{};
    for (final item in _snapshot?.history ?? const <TripHistoryItem>[]) {
      final destination = item.destination.location;
      final cell =
          '${(destination.latitude * 50).round()}:${(destination.longitude * 50).round()}';
      if (!visitedCells.add(cell)) continue;
      final lat1 = origin.latitude * math.pi / 180;
      final lat2 = destination.latitude * math.pi / 180;
      final deltaLon =
          (destination.longitude - origin.longitude) * math.pi / 180;
      final y = math.sin(deltaLon) * math.cos(lat2);
      final x =
          math.cos(lat1) * math.sin(lat2) -
          math.sin(lat1) * math.cos(lat2) * math.cos(deltaLon);
      final bearing = (math.atan2(y, x) * 180 / math.pi + 360) % 360;
      final sector = ((bearing + 45) ~/ 90) % 4;
      counts[sector] = (counts[sector] ?? 0) + 1;
    }
    return counts;
  }

  int? get _leastExploredDirection {
    if (widget.origin == null) return null;
    final counts = _directionCounts;
    if (counts.isEmpty) return null;
    var best = 0;
    for (var sector = 1; sector < 4; sector++) {
      if ((counts[sector] ?? 0) < (counts[best] ?? 0)) best = sector;
    }
    return best;
  }

  String _directionName(int sector) => switch (sector) {
    0 => _text('North', '北边'),
    1 => _text('East', '东边'),
    2 => _text('South', '南边'),
    _ => _text('West', '西边'),
  };

  Widget _unexploredDirectionCard() {
    final history = _snapshot?.history ?? const <TripHistoryItem>[];
    final sector = _leastExploredDirection;
    final counts = _directionCounts;
    final body = _loading
        ? _text(
            'Reading your journey history…',
            '正在读取你的旅程记录…',
          )
        : history.isEmpty
        ? _text(
            'Every direction is still new. Your first completed journeys will start building Waybi’s memory of the world you have travelled.',
            '现在每个方向都是新的。完成几次导航后，Waybi 就会开始建立你们一起走过的世界记忆。',
          )
        : sector == null
        ? _text(
            'Waybi needs your current location before it can compare where you have and have not travelled.',
            'Waybi 需要当前位置，才能比较你去过和还没怎么去过的方向。',
          )
        : _text(
            '${_directionName(sector)} is your least explored direction from here. Waybi remembers ${counts[sector] ?? 0} visited area${(counts[sector] ?? 0) == 1 ? '' : 's'} there.',
            '从这里出发，${_directionName(sector)}是你最少探索的方向。Waybi 在这个方向目前只记住了 ${counts[sector] ?? 0} 个到访区域。',
          );
    return _SectionCard(
      icon: Icons.explore_outlined,
      title: _text('Where Waybi has barely been', 'Waybi 还没怎么去过的方向'),
      body: body,
      trailing: IconButton.filledTonal(
        tooltip: _text('Choose a new destination', '选择一个新目的地'),
        onPressed: _loading
            ? null
            : () => Navigator.of(context).pop(DiscoverAction.newDestination),
        icon: const Icon(Icons.arrow_outward_rounded),
      ),
    );
  }

  String _lastVisited(DateTime? value) {
    if (value == null) return _text('A while ago', '有一阵子了');
    final days = DateTime.now().difference(value.toLocal()).inDays;
    if (days <= 0) return _text('Today', '今天');
    if (days == 1) return _text('Yesterday', '昨天');
    if (days < 30) return _text('$days days ago', '$days 天前');
    final months = (days / 30).floor();
    return _text('$months months ago', '$months 个月前');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final history = _snapshot?.history ?? const <TripHistoryItem>[];

    return Scaffold(
      appBar: AppBar(title: Text(_text('Discover', '发现'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [WaybiColors.ocean, WaybiColors.teal],
                ),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.travel_explore_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _text(
                      'Go somewhere Waybi does not know yet.',
                      '去一个 Waybi 还不认识的地方。',
                    ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _text(
                      'Discover is built around your journeys, not restaurant rankings. New roads and new memories will become more useful as you travel.',
                      '发现围绕你的旅程，而不是餐厅榜单。你走得越多，没走过的路和新的旅程记忆就越有意义。',
                    ),
                    style: const TextStyle(
                      color: Color(0xEFFFFFFF),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        Navigator.of(context)
                            .pop(DiscoverAction.newDestination),
                    icon: const Icon(Icons.navigation_rounded),
                    label: Text(_text('Choose somewhere new', '去个新地方')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              _text('Your world with Waybi', '你和 Waybi 走过的世界'),
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MemoryStat(
                    value: _loading ? '—' : '${history.length}',
                    label: _text('journeys', '段旅程'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MemoryStat(
                    value: _loading ? '—' : '$_uniqueDestinations',
                    label: _text('places remembered', '个记住的地方'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _unexploredDirectionCard(),
            const SizedBox(height: 12),
            _SectionCard(
              icon: Icons.landscape_rounded,
              title: _text('Scenic journeys', '风景路线'),
              body: _text(
                'Coastal, sunset and weekend drives will be route suggestions instead of generic nearby POIs.',
                '海岸线、日落和周末路线会成为真正的路线推荐，而不是泛泛的附近 POI。',
              ),
              trailing: Chip(label: Text(_text('Planned', '规划中'))),
            ),
            if (_leastRecentPlaces.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text(
                _text('Places worth rediscovering', '值得再去一次'),
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final item in _leastRecentPlaces)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.history_toggle_off_rounded),
                    title: Text(item.destination.name),
                    subtitle: Text(_lastVisited(item.createdAt)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () =>
                        Navigator.of(context).pop(DiscoverAction.trips),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Text(
              _text(
                'No ads, ratings or generic “top nearby” lists. Discover should get better because Waybi remembers your journeys.',
                '这里不做广告、评分榜和泛化的“附近热门”。发现应该因为 Waybi 记住了你的旅程而越来越好。',
              ),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryStat extends StatelessWidget {
  const _MemoryStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(label),
      ],
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(body, style: const TextStyle(height: 1.35)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        trailing,
      ],
    ),
  );
}
