import 'package:flutter/material.dart';

import '../domain/route_option.dart';
import '../theme/waybi_theme.dart';

// The home page's fixed chrome: shortcut chips (with commute ETAs), their
// editor and the bottom navigation bar.

/// Every shortcut a person can add. Keys are stored in preferences and
/// stay English; [quickActionTitle] is what people read.
const quickActionCatalog = [
  'Home',
  'Work',
  'Frequent',
  'Restaurants',
  'Shopping',
  'Gas',
];

String quickActionTitle(String action, String language) {
  String t(String en, String zh) => language == 'zh' ? zh : en;
  return switch (action) {
    'Home' => t('Home', '家'),
    'Work' => t('Work', '公司'),
    'Frequent' => t('Frequent', '常去'),
    'Restaurants' => t('Restaurants', '餐厅'),
    'Shopping' => t('Shopping', '购物'),
    // New Zealand calls it petrol.
    'Gas' => t('Petrol', '加油站'),
    _ => action,
  };
}

/// The search a shortcut runs, in the app language.
String quickActionQuery(String action, String language) {
  String t(String en, String zh) => language == 'zh' ? zh : en;
  return switch (action) {
    'Restaurants' => t('restaurants', '餐厅'),
    'Shopping' => t('shopping', '购物'),
    'Gas' => t('petrol station', '加油站'),
    _ => quickActionTitle(action, language),
  };
}

IconData quickActionIcon(String action) => switch (action) {
  'Home' => Icons.home_rounded,
  'Work' => Icons.work_rounded,
  'Frequent' => Icons.history_rounded,
  'Restaurants' => Icons.restaurant_rounded,
  'Shopping' => Icons.shopping_bag_rounded,
  'Gas' => Icons.local_gas_station_rounded,
  _ => Icons.place_rounded,
};

String quickCommuteEta(RouteOption route, String language) {
  String t(String en, String zh) => language == 'zh' ? zh : en;
  final minutes = (route.durationSeconds / 60).ceil().clamp(1, 999);
  if (minutes < 60) return t('$minutes min', '$minutes 分钟');
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (remainder == 0) return t('${hours}h', '$hours 小时');
  return t('${hours}h ${remainder}m', '$hours 小时 $remainder 分');
}

Color quickCommuteColor(RouteOption route) {
  final delay = route.trafficDelaySeconds ?? 0;
  if (delay >= 600) return WaybiColors.danger;
  if (delay >= 180 || route.traffic.trafficJam > 0) {
    return WaybiColors.warning;
  }
  return WaybiColors.ocean;
}

/// The row of shortcut chips under the search prompt. Home and Work show
/// their live drive time when known.
class QuickActionsBar extends StatelessWidget {
  const QuickActionsBar({
    super.key,
    required this.actions,
    required this.language,
    required this.commuteRoutes,
    required this.onAction,
    required this.onEdit,
  });

  final List<String> actions;
  final String language;
  final Map<String, RouteOption> commuteRoutes;
  final ValueChanged<String> onAction;
  final VoidCallback onEdit;

  Widget _label(BuildContext context, String action) {
    final route = commuteRoutes[action];
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          quickActionTitle(action, language),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        if (route != null) ...[
          const SizedBox(width: 6),
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: quickCommuteColor(route),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            quickCommuteEta(route, language),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 34,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final action in actions)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(
              avatar: Icon(
                quickActionIcon(action),
                size: 15,
                color: WaybiColors.ocean,
              ),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              backgroundColor: Theme.of(context).colorScheme.surface
                  .withValues(alpha: .96),
              side: BorderSide(color: WaybiColors.sky.withValues(alpha: .28)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
              label: _label(context, action),
              onPressed: () => onAction(action),
            ),
          ),
        SizedBox(
          width: 34,
          height: 34,
          child: IconButton.filledTonal(
            padding: EdgeInsets.zero,
            tooltip: language == 'zh' ? '编辑快捷入口' : 'Edit shortcuts',
            onPressed: onEdit,
            icon: const Icon(Icons.tune_rounded, size: 17),
          ),
        ),
      ],
    ),
  );
}

/// Reorder, add or remove shortcuts; Home and Work can be re-pointed.
void showQuickActionsEditor(
  BuildContext context, {
  required String language,
  required List<String> actions,
  required ValueChanged<String> onSetLocation,
  required Future<void> Function(List<String> actions) onDone,
}) {
  String t(String en, String zh) => language == 'zh' ? zh : en;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, updateSheet) => SafeArea(
        child: SizedBox(
          height: 430,
          child: Column(
            children: [
              ListTile(
                title: Text(t('Edit shortcuts', '编辑快捷入口')),
                subtitle: Text(
                  t(
                    'Drag to reorder. Remove or add shortcuts any time.',
                    '拖动排序，可随时移除或添加。',
                  ),
                ),
              ),
              Expanded(
                child: ReorderableListView(
                  onReorderItem: (oldIndex, newIndex) {
                    updateSheet(() {
                      final item = actions.removeAt(oldIndex);
                      actions.insert(newIndex, item);
                    });
                  },
                  children: [
                    for (final action in actions)
                      ListTile(
                        key: ValueKey(action),
                        title: Text(quickActionTitle(action, language)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (action == 'Home' || action == 'Work')
                              IconButton(
                                tooltip: t('Set location', '设置地点'),
                                icon: const Icon(
                                  Icons.edit_location_alt_outlined,
                                ),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  onSetLocation(action);
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () =>
                                  updateSheet(() => actions.remove(action)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Wrap(
                spacing: 4,
                children: [
                  for (final action in quickActionCatalog)
                    if (!actions.contains(action))
                      ActionChip(
                        label: Text('+ ${quickActionTitle(action, language)}'),
                        onPressed: () => updateSheet(() => actions.add(action)),
                      ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: () async {
                    await onDone(actions);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: Text(t('Done', '完成')),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Map · Discover · Start · Trips · Me.
class HomeBottomBar extends StatelessWidget {
  const HomeBottomBar({
    super.key,
    required this.language,
    required this.onMap,
    required this.onDiscover,
    required this.onStart,
    required this.onTrips,
    required this.onMe,
  });

  final String language;
  final VoidCallback onMap, onDiscover, onStart, onTrips, onMe;

  String t(String en, String zh) => language == 'zh' ? zh : en;

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String label, VoidCallback action) => Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: action,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .25),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2220351C),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Row(
            children: [
              item(Icons.map_outlined, t('Map', '地图'), onMap),
              item(
                Icons.travel_explore_outlined,
                t('Discover', '发现'),
                onDiscover,
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(17),
                  onTap: onStart,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 3,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 55,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [WaybiColors.ocean, WaybiColors.teal],
                            ),
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x30486B29),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.navigation_rounded,
                            size: 22,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t('Start', '出发'),
                          style: TextStyle(
                            color: WaybiColors.ocean,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              item(Icons.route_rounded, t('Trips', '行程'), onTrips),
              item(Icons.person_outline_rounded, t('Me', '我的'), onMe),
            ],
          ),
        ),
      ),
    );
  }
}
