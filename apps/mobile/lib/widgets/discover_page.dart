import 'package:flutter/material.dart';

import '../theme/waybi_theme.dart';
import 'trips_page.dart';

enum DiscoverAction { newDestination, trips }

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key, required this.language, required this.loader});

  final String language;
  final Future<TripsSnapshot> Function() loader;

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
            _SectionCard(
              icon: Icons.route_rounded,
              title: _text('Unexplored roads', '还没走过的路'),
              body: _text(
                'Waybi will use your journey history to distinguish roads you have travelled from roads that are still new to you. Route-level coverage comes next.',
                'Waybi 会用真实行程记录区分你走过和还没走过的道路。下一步会把记录细化到道路级。',
              ),
              trailing: Chip(label: Text(_text('Next', '下一步'))),
            ),
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
