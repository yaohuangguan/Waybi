import '../theme/waybi_theme.dart';

import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../domain/route_option.dart';
import '../domain/route_preference.dart';
import '../data/parking_repository.dart';
import 'waybi_bird.dart';

String _duration(int seconds, {bool isChinese = false}) {
  final duration = Duration(seconds: seconds);
  if (duration.inHours >= 1) {
    final minutes = duration.inMinutes.remainder(60);
    return minutes == 0
        ? (isChinese ? '${duration.inHours} 小时' : '${duration.inHours} hr')
        : (isChinese
              ? '${duration.inHours} 小时 $minutes 分钟'
              : '${duration.inHours} hr $minutes min');
  }
  final minutes = duration.inMinutes.clamp(1, 999);
  return isChinese ? '$minutes 分钟' : '$minutes min';
}

String _distance(int metres, {bool isChinese = false}) => metres >= 1000
    ? '${(metres / 1000).toStringAsFixed(metres < 10000 ? 1 : 0)} ${isChinese ? '公里' : 'km'}'
    : '$metres ${isChinese ? '米' : 'm'}';

String routeExplanation(
  RouteOption selected,
  List<RouteOption> routes, {
  bool isChinese = false,
}) {
  if (routes.isEmpty) return selected.description;
  final fastest = routes.reduce(
    (a, b) => a.durationSeconds <= b.durationSeconds ? a : b,
  );
  final facts = <String>[];
  final extra = selected.durationSeconds - fastest.durationSeconds;
  if (extra > 60) {
    facts.add(
      isChinese
          ? '比最快路线多 ${_duration(extra, isChinese: true)}'
          : '+${_duration(extra)} vs fastest',
    );
  } else if (selected.mode == WaybiTravelMode.drive) {
    facts.add(isChinese ? '当前最快路线' : 'Fastest available route');
  }
  final distanceDifference = selected.distanceMeters - fastest.distanceMeters;
  if (selected.id != fastest.id && distanceDifference.abs() >= 500) {
    facts.add(
      distanceDifference < 0
          ? (isChinese
                ? '少走 ${_distance(-distanceDifference, isChinese: true)}'
                : '${_distance(-distanceDifference)} shorter')
          : (isChinese
                ? '多走 ${_distance(distanceDifference, isChinese: true)}'
                : '${_distance(distanceDifference)} longer'),
    );
  }
  if ((selected.trafficDelaySeconds ?? 0) > 60) {
    facts.add(
      isChinese
          ? '拥堵增加 ${_duration(selected.trafficDelaySeconds!, isChinese: true)}'
          : '${_duration(selected.trafficDelaySeconds!)} traffic delay',
    );
  }
  if (selected.description.isNotEmpty) facts.add(selected.description);
  return facts.join(' · ');
}

IconData _icon(WaybiTravelMode mode) => switch (mode) {
  WaybiTravelMode.drive => Icons.directions_car_filled_rounded,
  WaybiTravelMode.transit => Icons.train_rounded,
  WaybiTravelMode.walk => Icons.directions_walk_rounded,
  WaybiTravelMode.bicycle => Icons.pedal_bike_rounded,
};

String _modeLabel(WaybiTravelMode mode, {required bool isChinese}) =>
    switch (mode) {
      WaybiTravelMode.drive => isChinese ? '驾车' : 'Drive',
      WaybiTravelMode.transit => isChinese ? '公交' : 'Transit',
      WaybiTravelMode.walk => isChinese ? '步行' : 'Walk',
      WaybiTravelMode.bicycle => isChinese ? '骑行' : 'Bike',
    };

String _cameraTypeLabel(String value, {required bool isChinese}) {
  if (!isChinese) return value;
  return switch (value.toLowerCase()) {
    'spot speed' => '定点测速',
    'average speed' => '区间测速',
    'red light' => '闯红灯',
    'red light + speed' => '闯红灯 + 测速',
    'bus / transit lane' => '公交 / 专用车道',
    'other' => '其他',
    _ => value,
  };
}

class RouteCameraSummary {
  const RouteCameraSummary({this.count = 0, this.types = const []});

  final int count;
  final List<String> types;
}

class RoutePreviewSheet extends StatelessWidget {
  const RoutePreviewSheet({
    super.key,
    required this.destinationTitle,
    required this.originTitle,
    required this.plan,
    required this.selectedMode,
    required this.selectedRouteId,
    required this.busy,
    required this.stopCount,
    required this.cameraCount,
    this.routeCameraSummaries = const {},
    this.routePreferenceSummaries = const {},
    this.canRequestTransit = false,
    required this.customOrigin,
    required this.onModeChanged,
    required this.onRouteSelected,
    required this.onStart,
    required this.onAddStop,
    required this.onSave,
    required this.isFavorite,
    required this.onFavorite,
    required this.onReview,
    required this.onClose,
    this.parkingPlaces = const [],
    this.selectedParkingId,
    this.finalDestinationTitle,
    this.parkingLoading = false,
    this.onParkingSelected,
    this.onDirectDestination,
    this.isChinese = false,
  });

  final String destinationTitle;
  final String originTitle;
  final RoutePlan plan;
  final WaybiTravelMode selectedMode;
  final String? selectedRouteId;
  final bool busy;
  final int stopCount;
  final int cameraCount;
  final Map<String, RouteCameraSummary> routeCameraSummaries;
  final Map<String, RoutePreferenceSummary> routePreferenceSummaries;
  final bool canRequestTransit;
  final bool customOrigin;
  final ValueChanged<WaybiTravelMode> onModeChanged;
  final ValueChanged<RouteOption> onRouteSelected;
  final VoidCallback onStart;
  final VoidCallback onAddStop;
  final VoidCallback onSave;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback onReview;
  final VoidCallback onClose;
  final List<ParkingPlace> parkingPlaces;
  final String? selectedParkingId;
  final String? finalDestinationTitle;
  final bool parkingLoading;
  final ValueChanged<ParkingPlace>? onParkingSelected;
  final VoidCallback? onDirectDestination;
  final bool isChinese;

  @override
  Widget build(BuildContext context) {
    final routes = plan.forMode(selectedMode).take(3).toList(growable: false);
    final preferences = assessRoutePreferences(
      routes,
      routePreferenceSummaries,
    );
    RouteOption? selected;
    for (final route in routes) {
      if (route.id == selectedRouteId) {
        selected = route;
        break;
      }
    }
    selected ??= routes.isEmpty ? null : routes.first;
    final fastestDuration = routes.isEmpty
        ? 0
        : routes
              .map((route) => route.durationSeconds)
              .reduce((a, b) => a < b ? a : b);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxSheetHeight = (screenHeight * .44).clamp(330.0, 420.0);

    return PointerInterceptor(
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 0,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxSheetHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 88),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          destinationTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const WaybiBird(size: 30),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                        tooltip: isFavorite
                            ? (isChinese ? '取消收藏' : 'Remove favorite')
                            : (isChinese ? '收藏' : 'Save favorite'),
                        onPressed: onFavorite,
                        icon: Icon(
                          isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: isFavorite
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                        tooltip: isChinese ? '我的评价' : 'My review',
                        onPressed: onReview,
                        icon: const Icon(Icons.rate_review_outlined),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 1, 2, 5),
                    child: Row(
                      children: [
                        Icon(
                          Icons.my_location_rounded,
                          size: 14,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            originTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 7),
                          child: Icon(Icons.arrow_forward_rounded, size: 15),
                        ),
                        Flexible(
                          child: Text(
                            destinationTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (finalDestinationTitle != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          isChinese
                              ? '前往 $finalDestinationTitle · 停车点'
                              : 'Parking for $finalDestinationTitle',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      for (final mode in WaybiTravelMode.values)
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final hasRoute = plan.forMode(mode).isNotEmpty;
                              final available =
                                  hasRoute ||
                                  (canRequestTransit &&
                                      mode == WaybiTravelMode.transit);
                              final disabled =
                                  !available ||
                                  (selectedParkingId != null &&
                                      mode != WaybiTravelMode.drive);
                              return InkWell(
                                onTap: disabled
                                    ? null
                                    : () => onModeChanged(mode),
                                borderRadius: BorderRadius.circular(14),
                                child: Opacity(
                                  opacity: disabled ? .35 : 1,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                      horizontal: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: selectedMode == mode
                                          ? Theme.of(context)
                                                .colorScheme
                                                .primaryContainer
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(
                                          _icon(mode),
                                          color: selectedMode == mode
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .onPrimaryContainer
                                              : Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                          size: 18,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _modeLabel(
                                            mode,
                                            isChinese: isChinese,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          !hasRoute
                                              ? (mode ==
                                                            WaybiTravelMode
                                                                .transit &&
                                                        canRequestTransit
                                                    ? (isChinese
                                                          ? '加载'
                                                          : 'Load')
                                                    : '—')
                                              : _duration(
                                                  plan
                                                      .forMode(mode)
                                                      .first
                                                      .durationSeconds,
                                                  isChinese: isChinese,
                                                ),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                  if (routes.isNotEmpty) ...[
                    const Divider(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        isChinese ? '路线选项' : 'Route options',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    for (var index = 0; index < routes.length; index++) ...[
                      _RouteOptionTile(
                        route: routes[index],
                        isChinese: isChinese,
                        active: routes[index].id == selected?.id,
                        fastestDuration: fastestDuration,
                        cameraSummary:
                            routeCameraSummaries[routes[index].id] ??
                            const RouteCameraSummary(),
                        preference: preferences[routes[index].id],
                        onTap: () => onRouteSelected(routes[index]),
                      ),
                      if (index != routes.length - 1) const SizedBox(height: 6),
                    ],
                  ],
                  if (selected != null) ...[
                    const SizedBox(height: 10),
                    _JourneyBrief(
                      route: selected,
                      cameraSummary:
                          routeCameraSummaries[selected.id] ??
                          const RouteCameraSummary(),
                      routeExplanationText: routeExplanation(
                        selected,
                        routes,
                        isChinese: isChinese,
                      ),
                      parkingPlaces: parkingPlaces,
                      selectedParkingId: selectedParkingId,
                      parkingLoading: parkingLoading,
                      isChinese: isChinese,
                    ),
                    if (selected.mode == WaybiTravelMode.drive &&
                        (selected.traffic.hasIssues ||
                            selected.warnings.isNotEmpty))
                      _TrafficCard(route: selected, isChinese: isChinese),
                    if (selected.mode == WaybiTravelMode.transit &&
                        selected.transit.isNotEmpty)
                      _TransitDetails(route: selected, isChinese: isChinese),
                    if (selectedMode == WaybiTravelMode.drive)
                      _ParkingChoices(
                        places: parkingPlaces,
                        selectedId: selectedParkingId,
                        finalDestinationTitle:
                            finalDestinationTitle ?? destinationTitle,
                        loading: parkingLoading,
                        onSelected: onParkingSelected,
                        onDirect: onDirectDestination,
                        isChinese: isChinese,
                      ),
                    if (customOrigin)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          isChinese ? '自定义起点仅用于路线预览；实时导航会从当前 GPS 位置开始。' : 'Custom origin is for route preview; live guidance starts from your GPS.',
                          maxLines: 2,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.tertiary,
                            fontSize: 10,
                            height: 1.2,
                          ),
                        ),
                      ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 8,
                              ),
                            ),
                            onPressed: selectedMode == WaybiTravelMode.transit
                                ? null
                                : onAddStop,
                            icon: const Icon(
                              Icons.add_location_alt_outlined,
                              size: 16,
                            ),
                            label: Text(
                              stopCount == 0
                                  ? (isChinese ? '添加途经点' : 'Add stop')
                                  : (isChinese
                                        ? '途经点 $stopCount'
                                        : 'Stops $stopCount'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 8,
                              ),
                            ),
                            onPressed: onSave,
                            icon: const Icon(
                              Icons.bookmark_border_rounded,
                              size: 16,
                            ),
                            label: Text(isChinese ? '保存' : 'Save', maxLines: 1),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteOptionTile extends StatelessWidget {
  const _RouteOptionTile({
    required this.route,
    required this.isChinese,
    required this.active,
    required this.fastestDuration,
    required this.cameraSummary,
    required this.preference,
    required this.onTap,
  });

  final RouteOption route;
  final bool isChinese;
  final bool active;
  final int fastestDuration;
  final RouteCameraSummary cameraSummary;
  final RoutePreferenceAssessment? preference;
  final VoidCallback onTap;

  String get _trafficLabel {
    if (route.traffic.trafficJam > 0) {
      return isChinese ? '拥堵较重' : 'Heavier traffic';
    }
    if (route.traffic.slow > 0) return isChinese ? '部分拥堵' : 'Some traffic';
    return isChinese ? '路况顺畅' : 'Light traffic';
  }

  Color _trafficColor() {
    if (route.traffic.trafficJam > 0) return WaybiColors.danger;
    if (route.traffic.slow > 0) return WaybiColors.warning;
    return WaybiColors.ocean;
  }

  List<String> get _preferenceLabels {
    final value = preference;
    if (value == null) return const [];
    final labels = <String>[];
    if (value.recommended) {
      labels.add(isChinese ? '综合推荐' : 'Recommended');
    }
    if (value.fastest) labels.add(isChinese ? '时间最短' : 'Fastest');
    if (value.shortest) labels.add(isChinese ? '距离最近' : 'Shortest');
    if (route.mode == WaybiTravelMode.drive && value.leastTraffic) {
      labels.add(isChinese ? '堵车更少' : 'Less traffic');
    }
    if (route.mode == WaybiTravelMode.drive && value.zeroCameras) {
      labels.add(isChinese ? '0 摄像头' : '0 cameras');
    }
    return labels.take(3).toList(growable: false);
  }

  List<Color> _trafficBars() {
    if (route.traffic.trafficJam > 0) {
      return const [
        WaybiColors.ocean,
        WaybiColors.warning,
        WaybiColors.warning,
        WaybiColors.danger,
        WaybiColors.danger,
      ];
    }
    if (route.traffic.slow > 0) {
      return const [
        WaybiColors.ocean,
        WaybiColors.ocean,
        WaybiColors.ocean,
        WaybiColors.warning,
        WaybiColors.warning,
      ];
    }
    return const [
      WaybiColors.ocean,
      WaybiColors.ocean,
      WaybiColors.ocean,
      WaybiColors.ocean,
      WaybiColors.ocean,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fastest = route.durationSeconds == fastestDuration;
    final delay = route.trafficDelaySeconds;
    final description = route.description.trim().isNotEmpty
        ? route.description.trim()
        : fastest
        ? (isChinese ? '推荐路线' : 'Best route')
        : (isChinese ? '备选路线' : 'Alternative');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: active
              ? scheme.primaryContainer.withValues(alpha: .72)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? scheme.primary : theme.dividerColor,
            width: active ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: active ? scheme.primary : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _icon(route.mode),
                size: 17,
                color: active ? scheme.onPrimary : scheme.primary,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _duration(route.durationSeconds, isChinese: isChinese),
                    style: TextStyle(
                      color: active ? scheme.primary : scheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${_distance(route.distanceMeters, isChinese: isChinese)} · $description'
                    '${delay != null && delay > 60 ? (isChinese ? ' · 拥堵 ${_duration(delay, isChinese: true)}' : ' · ${_duration(delay)} traffic') : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_preferenceLabels.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final label in _preferenceLabels)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  label == (isChinese ? '综合推荐' : 'Recommended')
                                  ? scheme.primaryContainer
                                  : scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color:
                                    label ==
                                        (isChinese ? '综合推荐' : 'Recommended')
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (route.mode == WaybiTravelMode.drive) ...[
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: cameraSummary.count > 0
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: cameraSummary.count > 0
                              ? scheme.primary.withValues(alpha: .38)
                              : theme.dividerColor,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.photo_camera_rounded,
                            size: 13,
                            color: cameraSummary.count > 0
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              cameraSummary.count > 0
                                  ? (isChinese
                                        ? '${cameraSummary.count} 个摄像头${cameraSummary.types.isEmpty ? '' : ' · ${cameraSummary.types.take(2).map((type) => _cameraTypeLabel(type, isChinese: true)).join(' + ')}'}'
                                        : '${cameraSummary.count} camera${cameraSummary.count == 1 ? '' : 's'}${cameraSummary.types.isEmpty ? '' : ' · ${cameraSummary.types.take(2).join(' + ')}'}')
                                  : (isChinese
                                        ? '未匹配到摄像头'
                                        : 'No cameras matched'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cameraSummary.count > 0
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 84,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _trafficLabel,
                    style: TextStyle(
                      color: _trafficColor(),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (final color in _trafficBars()) ...[
                        Container(
                          width: 10,
                          height: 4,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 2),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JourneyBrief extends StatelessWidget {
  const _JourneyBrief({
    required this.route,
    required this.cameraSummary,
    required this.routeExplanationText,
    required this.parkingPlaces,
    required this.selectedParkingId,
    required this.parkingLoading,
    required this.isChinese,
  });

  final RouteOption route;
  final RouteCameraSummary cameraSummary;
  final String routeExplanationText;
  final List<ParkingPlace> parkingPlaces;
  final String? selectedParkingId;
  final bool parkingLoading;
  final bool isChinese;

  String _arrivalLabel(BuildContext context) {
    final arrival = DateTime.now().add(
      Duration(seconds: route.durationSeconds),
    );
    return TimeOfDay.fromDateTime(arrival).format(context);
  }

  String _trafficLabel() {
    final delay = route.trafficDelaySeconds ?? 0;
    if (delay > 60) {
      return isChinese
          ? '+${_duration(delay, isChinese: true)}'
          : '+${_duration(delay)}';
    }
    if (route.traffic.trafficJam > 0) return isChinese ? '拥堵' : 'Heavy';
    if (route.traffic.slow > 0) return isChinese ? '缓行' : 'Slow';
    return isChinese ? '顺畅' : 'Clear';
  }

  String _parkingLabel() {
    if (selectedParkingId != null) {
      for (final place in parkingPlaces) {
        if (place.id == selectedParkingId) {
          return isChinese ? '已选 ${place.name}' : 'Selected';
        }
      }
      return isChinese ? '已选择' : 'Selected';
    }
    if (parkingLoading) return isChinese ? '查找中' : 'Checking';
    if (parkingPlaces.isEmpty) return isChinese ? '暂无数据' : 'No data';
    final nearest = parkingPlaces.reduce(
      (a, b) => a.distanceMeters <= b.distanceMeters ? a : b,
    );
    return nearest.distanceMeters < 1000
        ? '${nearest.distanceMeters.round()} ${isChinese ? '米' : 'm'}'
        : '${(nearest.distanceMeters / 1000).toStringAsFixed(1)} ${isChinese ? '公里' : 'km'}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final explanation = routeExplanationText.trim();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                isChinese ? '行前摘要' : 'Journey brief',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                _distance(route.distanceMeters, isChinese: isChinese),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _BriefStat(
                icon: Icons.schedule_rounded,
                label: isChinese ? '预计到达' : 'Arrive',
                value: _arrivalLabel(context),
              ),
              _BriefStat(
                icon: Icons.traffic_rounded,
                label: isChinese ? '交通' : 'Traffic',
                value: _trafficLabel(),
              ),
              if (route.mode == WaybiTravelMode.drive)
                _BriefStat(
                  icon: Icons.photo_camera_rounded,
                  label: isChinese ? '摄像头' : 'Cameras',
                  value: '${cameraSummary.count}',
                ),
              if (route.mode == WaybiTravelMode.drive)
                _BriefStat(
                  icon: Icons.local_parking_rounded,
                  label: isChinese ? '停车' : 'Parking',
                  value: _parkingLabel(),
                ),
            ],
          ),
          if (explanation.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              explanation,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 10.5,
                height: 1.25,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BriefStat extends StatelessWidget {
  const _BriefStat({
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
      constraints: const BoxConstraints(minWidth: 108),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 5),
          Text(
            '$label ',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({required this.route, required this.isChinese});

  final RouteOption route;
  final bool isChinese;

  @override
  Widget build(BuildContext context) {
    final jam = route.traffic.trafficJam;
    final slow = route.traffic.slow;
    final text = jam > 0
        ? (isChinese
              ? '前方有 $jam 段严重拥堵'
              : '$jam heavy-traffic section${jam == 1 ? '' : 's'} ahead')
        : (isChinese
              ? '前方有 $slow 段缓行'
              : '$slow slow section${slow == 1 ? '' : 's'} ahead');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.tertiary.withValues(alpha: .35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              route.warnings.isNotEmpty
                  ? '$text · ${isChinese && route.warnings.first == 'This route includes a highway.' ? '路线包含高速公路路段' : route.warnings.first}'
                  : text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransitDetails extends StatelessWidget {
  const _TransitDetails({required this.route, required this.isChinese});

  final RouteOption route;
  final bool isChinese;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          for (var index = 0; index < route.transit.length; index++) ...[
            if (index > 0) const Divider(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.directions_transit_rounded, size: 20),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          route.transit[index].lineName,
                          route.transit[index].headsign,
                        ].where((value) => value.isNotEmpty).join(' → '),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${route.transit[index].departureStop} → '
                        '${route.transit[index].arrivalStop}'
                        '${route.transit[index].stopCount > 0 ? (isChinese ? ' · ${route.transit[index].stopCount} 站' : ' · ${route.transit[index].stopCount} stops') : ''}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ParkingChoices extends StatelessWidget {
  const _ParkingChoices({
    required this.places,
    required this.selectedId,
    required this.finalDestinationTitle,
    required this.loading,
    required this.onSelected,
    required this.onDirect,
    required this.isChinese,
  });

  final List<ParkingPlace> places;
  final String? selectedId;
  final String finalDestinationTitle;
  final bool loading;
  final ValueChanged<ParkingPlace>? onSelected;
  final VoidCallback? onDirect;
  final bool isChinese;

  String _walkDistance(double metres) => metres >= 1000
      ? '${(metres / 1000).toStringAsFixed(1)} ${isChinese ? '公里' : 'km'}'
      : '${metres.round()} ${isChinese ? '米' : 'm'}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.local_parking_rounded,
                  color: scheme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isChinese ? '附近停车' : 'Nearby parking',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            isChinese
                ? '$finalDestinationTitle · 先驾车停车，再步行至终点'
                : '$finalDestinationTitle · Drive, park, then continue on foot',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
          ),
          if (onDirect != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onDirect,
                icon: const Icon(Icons.route_rounded, size: 17),
                label: Text(
                  isChinese ? '直接前往终点' : 'Route straight to destination',
                ),
              ),
            ),
          if (!loading && places.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                isChinese ? '附近暂无停车数据。' : 'No nearby parking data found.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          if (places.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: places.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final place = places[index];
                  final active = selectedId == place.id;
                  return InkWell(
                    onTap: () => onSelected?.call(place),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 200,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: active
                            ? scheme.primaryContainer
                            : scheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: active
                              ? scheme.primary
                              : scheme.outlineVariant,
                          width: active ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            place.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isChinese
                                ? '距终点 ${_walkDistance(place.distanceMeters)} · ${place.source}'
                                : '${_walkDistance(place.distanceMeters)} from destination · ${place.source}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                          if (place.address.isNotEmpty)
                            Text(
                              place.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          const Spacer(),
                          Text(
                            place.totalSpaces == null
                                ? (isChinese ? '选择停车点' : 'Select parking')
                                : isChinese
                                ? '总车位 ${place.totalSpaces}'
                                      '${place.mobilitySpaces == null ? '' : ' · 无障碍 ${place.mobilitySpaces}'}'
                                : '${place.totalSpaces} total spaces'
                                      '${place.mobilitySpaces == null ? '' : ' · ${place.mobilitySpaces} accessible'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ParkingContinuationCard extends StatelessWidget {
  const ParkingContinuationCard({
    super.key,
    required this.destinationTitle,
    required this.parkingTitle,
    required this.onContinue,
    required this.onEnd,
    this.isChinese = false,
    this.carRemembered = false,
  });

  final String destinationTitle;
  final String parkingTitle;
  final VoidCallback onContinue;
  final VoidCallback onEnd;
  final bool isChinese;
  final bool carRemembered;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PointerInterceptor(
      child: Material(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_parking_rounded, color: scheme.primary),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        isChinese ? '驾车路段已结束' : 'Driving leg ended',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '$parkingTitle → $destinationTitle',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (carRemembered) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.directions_car_filled_rounded,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isChinese ? '已记住停车位置，可从地图右侧小车按钮返回' : 'Car location remembered · use the car button on the map to return',
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onEnd,
                        child: Text(isChinese ? '结束行程' : 'End trip'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: onContinue,
                        icon: const Icon(Icons.directions_walk_rounded),
                        label: Text(isChinese ? '继续步行' : 'Continue on foot'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
