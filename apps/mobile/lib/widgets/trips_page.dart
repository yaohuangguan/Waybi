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

class TripsSnapshot {
  const TripsSnapshot({
    required this.quickPlaces,
    required this.quickRoutes,
    required this.recent,
    required this.history,
  });

  final Map<String, TripDestination> quickPlaces;
  final Map<String, RouteOption> quickRoutes;
  final List<TripDestination> recent;
  final List<TripHistoryItem> history;
}

class TripsResult {
  const TripsResult.select(this.destination) : configureLabel = null;
  const TripsResult.configure(this.configureLabel) : destination = null;

  final TripDestination? destination;
  final String? configureLabel;
}

class TripsPage extends StatefulWidget {
  const TripsPage({super.key, required this.language, required this.loader});

  final String language;
  final Future<TripsSnapshot> Function() loader;

  @override
  State<TripsPage> createState() => _TripsPageState();
}

class _TripsPageState extends State<TripsPage> {
  TripsSnapshot? _snapshot;
  bool _loading = true;
  String? _error;

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
