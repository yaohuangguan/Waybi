import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/map_layer_settings.dart';
import '../domain/road_event.dart';
import '../domain/route_option.dart';
import '../drive/navigation_language.dart';
import '../widgets/waybi_format.dart';

import '../domain/safety_camera.dart';
import '../domain/transit_lane.dart';
import '../domain/transit_review_corridor.dart';
import '../theme/waybi_theme.dart';
import '../widgets/road_event_details_sheet.dart';
import '../domain/map_provider.dart';

// Sheets and dialogs the home page opens. Each takes the app language and
// keeps the page's `_text(en, zh)` copy pattern until the gen-l10n pass.

/// The localized name of a road event type.
String roadEventLabel(RoadEventType type, String language) {
  String t(String en, String zh) => language == 'zh' ? zh : en;
  return switch (type) {
    RoadEventType.incident => t('Crash / hazard', '事故 / 危险'),
    RoadEventType.roadworks => t('Roadworks', '道路施工'),
    RoadEventType.roadClosure => t('Road closed', '道路封闭'),
    RoadEventType.congestion => t('Heavy traffic', '严重拥堵'),
    RoadEventType.flooding => t('Flooding', '积水 / 洪水'),
    RoadEventType.slip => t('Slip / debris', '滑坡 / 道路杂物'),
    _ => t('Road report', '道路报告'),
  };
}

/// The one-time welcome dialog, unless it was already dismissed.
Future<void> maybeShowCoreOnboarding(
  BuildContext context,
  String language,
) async {
  String t(String en, String zh) => language == 'zh' ? zh : en;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('waybi.onboarding.core.v1') == true) return;
  if (!context.mounted) return;
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 6),
      contentPadding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
      title: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [WaybiColors.ocean, WaybiColors.teal],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.navigation_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              t('Welcome to Waybi', '欢迎使用 Waybi'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _OnboardingFeature(
            icon: Icons.route_rounded,
            title: t('Navigation first', '专注导航'),
            body: t(
              'Clear route guidance, traffic-aware routing and a focused Drive Mode.',
              '清晰路线指引、实时交通路线，以及专注驾驶的 Drive Mode。',
            ),
          ),
          _OnboardingFeature(
            icon: Icons.shield_outlined,
            title: t('Road Intelligence', '道路情报'),
            body: t(
              'Worldwide road reports and route guidance, with official safety cameras in New Zealand.',
              '全球道路上报与路线提示，新西兰另有官方安全摄像头数据。',
            ),
          ),
          _OnboardingFeature(
            icon: Icons.add_alert_rounded,
            title: t('Report the road', '上报道路情况'),
            body: t(
              'Share crashes, hazards, roadworks, flooding and congestion with other Waybi drivers.',
              '向其他 Waybi 用户分享事故、危险、施工、积水与拥堵。',
            ),
          ),
          _OnboardingFeature(
            icon: Icons.explore_rounded,
            title: t('Made for New Zealand', '为新西兰道路设计'),
            body: t(
              'Waybi location marker, NZ road data and a calm lime driving interface.',
              'Waybi 定位标记、新西兰道路数据，以及 Waybi lime 驾驶界面。',
            ),
          ),
        ],
      ),
      actions: [
        FilledButton.icon(
          onPressed: () async {
            await prefs.setBool('waybi.onboarding.core.v1', true);
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          },
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(t('Start exploring', '开始探索')),
        ),
      ],
    ),
  );
}

/// Details of a safety camera marker.
Future<void> showCameraDetailsSheet(
  BuildContext context,
  SafetyCamera camera,
  String language,
) async {
  String t(String en, String zh) => language == 'zh' ? zh : en;
  final kind = CameraKindLabel.fromCamera(camera);
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      Widget row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: scheme.primary),
            const SizedBox(width: 11),
            SizedBox(
              width: 72,
              child: Text(
                label,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );

      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    Icons.photo_camera_rounded,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kind.localizedLabel(language),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        camera.location,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            row(Icons.map_outlined, t('Region', '区域'), camera.region),
            row(Icons.location_city_rounded, t('Suburb', '地区'), camera.suburb),
            row(Icons.pin_drop_outlined, t('Location', '位置'), camera.location),
            row(Icons.speed_rounded, t('Camera type', '摄像头类型'), camera.type),
            row(
              Icons.gps_fixed_rounded,
              'GPS',
              '${camera.latitude.toStringAsFixed(6)}, '
                  '${camera.longitude.toStringAsFixed(6)}',
            ),
            const SizedBox(height: 4),
            Text(
              t(
                'Published by NZ Transport Agency · fixed safety camera location',
                'NZ Transport Agency 公开 · 固定安全摄像头位置',
              ),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5),
            ),
          ],
        ),
      );
    },
  );
}

/// Hours and rules of a published bus or transit lane.
Future<void> showTransitLaneDetailsSheet(
  BuildContext context,
  TransitLane lane,
  String language,
) async {
  String t(String en, String zh) => language == 'zh' ? zh : en;
  final active = lane.schedule.activeAt(DateTime.now());
  final status = switch (active) {
    true => t('Operating now', '当前生效'),
    false => t('Outside published hours', '当前不在公布时段内'),
    null => t('Hours not confirmed', '时段尚未确认'),
  };
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lane.roadName.isEmpty ? lane.label(language) : lane.roadName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(lane.label(language)),
          const SizedBox(height: 8),
          Text(status, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(lane.schedule.label(language)),
          const SizedBox(height: 14),
          Text(
            t(
              'Auckland Transport published lane geometry. Dashed lines do not mean the entire road is restricted. Check roadside signs before entering.',
              '奥克兰交通局公布的专用车道位置。虚线不代表整条道路禁止通行，驶入前请以现场标志为准。',
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '© Auckland Transport · CC BY 4.0',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

/// A review-only council corridor, with its source.
Future<void> showTransitReviewDetailsSheet(
  BuildContext context,
  TransitReviewCorridor corridor,
  String language,
) async {
  String t(String en, String zh) => language == 'zh' ? zh : en;
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            corridor.roadName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(corridor.city),
          const SizedBox(height: 12),
          Text(
            t(
              'Review-only road corridor · Not verified lane limits',
              '待核实道路走廊 · 不是已确认的公交车道边界',
            ),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.orange,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            language == 'zh' ? corridor.ruleSummaryZh : corridor.ruleSummary,
          ),
          const SizedBox(height: 12),
          Text(
            t(
              'This line is an approximate council STREET CENTRELINE, not the physical bus lane. Published rules may cover only part of the road and one direction. It is not used for route blocking or automatic lane alerts. Always follow roadside signs.',
              '此线仅为市议会道路中心线示意，不是实际公交车道的精确边界。官方规则可能只覆盖部分路段或某个方向；Waybi 不会据此封禁路线或自动提醒违规。请以现场路牌为准。',
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          Text(
            '© ${corridor.authority}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          TextButton.icon(
            onPressed: () => unawaited(
              launchUrl(
                Uri.parse(corridor.ruleSource),
                mode: LaunchMode.externalApplication,
              ),
            ),
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(t('Council source', '查看市议会来源')),
          ),
        ],
      ),
    ),
  );
}

/// Details of a road event marker.
Future<void> showRoadEventDetails(
  BuildContext context,
  RoadEvent event,
  String language,
) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .8,
    ),
    builder: (_) => RoadEventDetailsSheet(
      event: event,
      title: roadEventLabel(event.type, language),
      language: language,
    ),
  );
}

class _OnboardingFeature extends StatelessWidget {
  const _OnboardingFeature({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: WaybiColors.ice,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: WaybiColors.ocean, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: WaybiColors.deepOcean,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: WaybiColors.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Lets the driver pick a road issue type; returns (api type, English description).
Future<(String, String)?> showRoadReportPicker(
  BuildContext context,
  String language,
) async {
  String t(String en, String zh) => language == 'zh' ? zh : en;
  final choices = <(String, String, String, IconData)>[
    ('incident', 'Crash / hazard', '事故 / 危险', Icons.car_crash_rounded),
    ('roadworks', 'Roadworks', '道路施工', Icons.construction_rounded),
    ('roadClosure', 'Road closed', '道路封闭', Icons.block_rounded),
    ('congestion', 'Heavy traffic', '严重拥堵', Icons.traffic_rounded),
    ('flooding', 'Flooding', '积水 / 洪水', Icons.water_rounded),
    ('slip', 'Slip / debris', '滑坡 / 道路杂物', Icons.landslide_rounded),
  ];
  final selected = await showModalBottomSheet<(String, String)>(
    context: context,
    useSafeArea: true,
    showDragHandle: false,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).dividerColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              t('Report road issue', '上报道路情况'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              t(
                'Reports are shared with Waybi drivers for about 2 hours.',
                '上报内容将在约 2 小时内共享给 Waybi 驾驶用户。',
              ),
            ),
          ),
          for (final choice in choices)
            ListTile(
              leading: Icon(choice.$4, color: WaybiColors.ocean),
              title: Text(t(choice.$2, choice.$3)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(sheetContext, (choice.$1, choice.$2)),
            ),
        ],
      ),
    ),
  );
  return selected;
}

/// The private review editor; returns the new rating and comment, or null
/// when cancelled.
Future<({int rating, String comment})?> showPlaceReviewDialog(
  BuildContext context, {
  required String language,
  required String placeName,
  int initialRating = 5,
  String initialComment = '',
}) => showDialog<({int rating, String comment})>(
  context: context,
  builder: (_) => _PlaceReviewDialog(
    language: language,
    placeName: placeName,
    initialRating: initialRating,
    initialComment: initialComment,
  ),
);

class _PlaceReviewDialog extends StatefulWidget {
  const _PlaceReviewDialog({
    required this.language,
    required this.placeName,
    required this.initialRating,
    required this.initialComment,
  });

  final String language;
  final String placeName;
  final int initialRating;
  final String initialComment;

  @override
  State<_PlaceReviewDialog> createState() => _PlaceReviewDialogState();
}

class _PlaceReviewDialogState extends State<_PlaceReviewDialog> {
  late final _comment = TextEditingController(text: widget.initialComment);
  late var _rating = widget.initialRating;

  String t(String en, String zh) => widget.language == 'zh' ? zh : en;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      t('My review · ${widget.placeName}', '我的评价 · ${widget.placeName}'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<int>(
          initialValue: _rating,
          decoration: InputDecoration(labelText: t('Rating', '评分')),
          items: [
            for (var value = 1; value <= 5; value++)
              DropdownMenuItem(
                value: value,
                child: Text('${'★' * value} ($value/5)'),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _rating = value);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _comment,
          maxLines: 4,
          maxLength: 2000,
          decoration: InputDecoration(
            labelText: t('Private comment', '私人备注'),
            border: const OutlineInputBorder(),
          ),
        ),
        Text(
          t(
            'Saved to Waybi only; not published to Google.',
            '仅保存在 Waybi，不会发布到 Google。',
          ),
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(t('Cancel', '取消')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, (
          rating: _rating,
          comment: _comment.text.trim(),
        )),
        child: Text(t('Save', '保存')),
      ),
    ],
  );
}

/// The turn list of the active route, over the map fitted to it.
Future<void> showDirectionsSheet(
  BuildContext context,
  RouteOption route, {
  required String language,
  required double sheetHeight,
}) async {
  String t(String en, String zh) => language == 'zh' ? zh : en;
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final dark = theme.brightness == Brightness.dark;
  final sheetColor = dark ? WaybiColors.darkOcean : scheme.surface;
  final headerColor = dark ? WaybiColors.darkSurface : scheme.surface;
  final badgeColor = dark
      ? WaybiColors.deepTeal.withValues(alpha: .38)
      : scheme.primaryContainer;
  final badgeForeground = dark ? WaybiColors.sky : scheme.onPrimaryContainer;
  final secondaryColor = dark
      ? WaybiColors.darkTextSecondary
      : scheme.onSurfaceVariant;
  final dividerColor = dark ? WaybiColors.darkBorder : theme.dividerColor;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: sheetColor,
    barrierColor: Colors.black.withValues(alpha: dark ? .46 : .28),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    clipBehavior: Clip.antiAlias,
    constraints: BoxConstraints(maxHeight: sheetHeight),
    builder: (sheetContext) {
      return Material(
        color: sheetColor,
        elevation: 0,
        child: Column(
          children: [
            ColoredBox(
              color: headerColor,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
                child: Column(
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: dividerColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            Icons.route_rounded,
                            color: badgeForeground,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t('Directions', '路线指引'),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                t(
                                  '${(route.distanceMeters / 1000).toStringAsFixed(1)} km · ${route.steps.length} steps',
                                  '${(route.distanceMeters / 1000).toStringAsFixed(1)} 公里 · ${route.steps.length} 个步骤',
                                ),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: secondaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: t('Close', '关闭'),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: dividerColor),
            Expanded(
              child: route.steps.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          t(
                            'Turn list is not available for this route.',
                            '这条路线暂时没有逐步指引。',
                          ),
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 3, 12, 18),
                      itemCount: route.steps.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: dividerColor),
                      itemBuilder: (context, index) {
                        final step = route.steps[index];
                        return ListTile(
                          dense: true,
                          minTileHeight: 48,
                          visualDensity: VisualDensity.compact,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          leading: Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: badgeColor,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: badgeForeground,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          title: Text(
                            routeStepInstruction(step, language),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          trailing: Text(
                            formatDistance(step.distanceMeters, language),
                            style: TextStyle(
                              color: secondaryColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}

/// Favourite places and saved routes; Google-only records explain why
/// they cannot open here.
void showSavedSheet(
  BuildContext context, {
  required String language,
  required List<String> savedRoutes,
  required List<Map<String, dynamic>> favoritePlaces,
  required ValueChanged<PlaceSummary> onPlace,
  required ValueChanged<String> onNotice,
}) {
  String t(String en, String zh) => language == 'zh' ? zh : en;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * .65,
      child: ListView(
        children: [
          ListTile(
            title: Text(
              t('Saved places & routes', '收藏地点与路线'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          for (final place in favoritePlaces)
            ListTile(
              leading: const Icon(Icons.bookmark_rounded),
              title: Text(
                place['name']?.toString() ?? t('Saved place', '收藏地点'),
              ),
              onTap: () {
                final latitude = place['latitude'],
                    longitude = place['longitude'];
                if (latitude is! num || longitude is! num) return;
                final id = place['placeId']?.toString() ?? '';
                if ((id.isNotEmpty) &&
                    !id.startsWith('coords:') &&
                    !id.startsWith('osm:')) {
                  Navigator.of(sheetContext).pop();
                  onNotice(
                    t(
                      'This saved Google place is available on Google Maps.',
                      '这个收藏的 Google 地点请在 Google 地图中查看。',
                    ),
                  );
                  return;
                }
                Navigator.of(sheetContext).pop();
                onPlace(
                  PlaceSummary(
                    name: place['name']?.toString() ?? t('Saved place', '收藏地点'),
                    address: place['address']?.toString() ?? '',
                    location: GeoPoint(
                      latitude.toDouble(),
                      longitude.toDouble(),
                    ),
                    reference: id.startsWith('osm:')
                        ? ProviderReference('osm', id.substring(4))
                        : null,
                  ),
                );
              },
            ),
          for (final record in savedRoutes)
            Builder(
              builder: (context) {
                try {
                  final data = jsonDecode(record) as Map<String, dynamic>;
                  final place = data['destination'] as Map<String, dynamic>;
                  return ListTile(
                    leading: const Icon(Icons.route_rounded),
                    title: Text(
                      place['name']?.toString() ?? t('Saved route', '收藏路线'),
                    ),
                    onTap: () {
                      if ((data['provider'] != 'independent')) {
                        Navigator.of(sheetContext).pop();
                        onNotice(
                          t(
                            'This saved route belongs to Google Maps.',
                            '这条收藏路线来自 Google 地图。',
                          ),
                        );
                        return;
                      }
                      Navigator.of(sheetContext).pop();
                      onPlace(
                        PlaceSummary(
                          name:
                              place['name']?.toString() ??
                              t('Saved route', '收藏路线'),
                          location: GeoPoint(
                            (place['latitude'] as num).toDouble(),
                            (place['longitude'] as num).toDouble(),
                          ),
                        ),
                      );
                    },
                  );
                } catch (_) {
                  return const SizedBox.shrink();
                }
              },
            ),
          if (savedRoutes.isEmpty && favoritePlaces.isEmpty)
            ListTile(
              title: Text(t('No saved places yet', '还没有收藏地点')),
              subtitle: Text(
                t(
                  'Tap the bookmark on a place to keep it here.',
                  '打开地点后点收藏，就会出现在这里。',
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
