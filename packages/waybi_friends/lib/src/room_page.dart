import 'package:flutter/material.dart';

import 'friend_strings.dart';
import 'game_controller.dart';
import 'journey_engine.dart';
import 'living_room_scene.dart';
import 'packing_status.dart';
import 'room_life.dart';
import 'theme.dart';
import 'travel_item_art.dart';

class RoomPage extends StatefulWidget {
  const RoomPage({
    super.key,
    required this.controller,
    this.showHeader = true,
    this.showPrototypeControls = true,
  });
  final GameController controller;
  final bool showHeader, showPrototypeControls;
  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  String? thought;
  DateTime? thoughtUntil;
  GameController get controller => widget.controller;
  void _think(String text) {
    if (!mounted) return;
    setState(() {
      thought = text;
      thoughtUntil = controller.clock().add(const Duration(seconds: 5));
    });
  }

  @override
  Widget build(BuildContext context) {
    final active = controller.state.activeJourney;
    return ColoredBox(
      color: WwhColors.cream,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Column(
          children: [
            if (widget.showHeader)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  friendText(context, "Waybi's Way Home", '伙伴的小屋'),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
            SegmentedButton<HomeScene>(
              segments: [
                ButtonSegment(
                  value: HomeScene.room,
                  icon: const Icon(Icons.home_rounded),
                  label: Text(friendText(context, 'Room', '小屋')),
                ),
                ButtonSegment(
                  value: HomeScene.garden,
                  icon: const Icon(Icons.local_florist_rounded),
                  label: Text(friendText(context, 'Garden', '花园')),
                ),
              ],
              selected: {controller.roomLife.scene},
              onSelectionChanged: (value) =>
                  controller.changeScene(value.single),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: LivingRoomScene(
                life: controller.roomLife,
                clock: controller.clock,
                thought: thought,
                thoughtUntil: thoughtUntil,
                waybiAway: controller.waybiAway,
                onWaybiTap: () => _openFriend(FriendKind.waybi),
                onCloverTap: () => _openFriend(FriendKind.clover),
                onSettTap: () => _openFriend(FriendKind.sett),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                for (final kind in FriendKind.values)
                  ActionChip(
                    key: ValueKey('friend-action-${kind.name}'),
                    avatar: Icon(
                      controller.isAway(kind)
                          ? Icons.explore_outlined
                          : Icons.pets_rounded,
                      size: 16,
                    ),
                    label: Text(friendName(kind)),
                    onPressed: () => _openFriend(kind),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: WwhColors.paper,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  const Icon(Icons.backpack_rounded, color: WwhColors.moss),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          active == null
                              ? friendText(
                                  context,
                                  'A little journey?',
                                  '出去探索一下？',
                                )
                              : friendText(
                                  context,
                                  '${friendName(active.traveller)} is exploring',
                                  '${friendName(active.traveller)} 在外探索',
                                ),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          active == null
                              ? friendText(
                                  context,
                                  'Choose a friend and pack a small bag.',
                                  '选一位伙伴，带上小背包。',
                                )
                              : friendText(
                                  context,
                                  'Home in ${remainingJourneyTime(context, active.returnAt.difference(controller.clock()))}',
                                  '预计 ${remainingJourneyTime(context, active.returnAt.difference(controller.clock()))} 后到家',
                                ),
                          style: const TextStyle(
                            color: WwhColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (active == null)
                    FilledButton(
                      onPressed: () => _pack(FriendKind.waybi),
                      child: Text(friendText(context, 'Pack', '打包')),
                    ),
                  if (active != null && widget.showPrototypeControls)
                    TextButton(
                      onPressed: controller.bringWaybiHomeForPrototype,
                      child: Text(friendText(context, 'Bring home', '回家')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFriend(FriendKind kind) async {
    final name = friendName(kind);
    final away = controller.isAway(kind);
    final locale = Localizations.localeOf(context);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: WwhColors.paper,
      builder: (sheetContext) => Localizations.override(
        context: sheetContext,
        locale: locale,
        child: Builder(
          builder: (context) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(name, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 10),
                if (away)
                  Text(
                    friendText(
                      context,
                      '$name is on an adventure. Home in ${remainingJourneyTime(context, controller.state.activeJourney!.returnAt.difference(controller.clock()))}.',
                      '$name 正在旅行，预计 ${remainingJourneyTime(context, controller.state.activeJourney!.returnAt.difference(controller.clock()))} 后回家。',
                    ),
                  )
                else ...[
                  Text(
                    friendText(
                      context,
                      switch (kind) {
                        FriendKind.clover => 'A sunny window, a quiet friend.',
                        FriendKind.sett =>
                          'Always ready for another game of fetch.',
                        FriendKind.waybi =>
                          'A little kiwi with a curious heart.',
                      },
                      switch (kind) {
                        FriendKind.clover => '陪 Clover 去晒晒太阳。',
                        FriendKind.sett => 'Sett 随时准备和你玩球。',
                        FriendKind.waybi => '陪好奇的小几维鸟看看地图。',
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    key: ValueKey('interact-${kind.name}'),
                    onPressed: () async {
                      Navigator.pop(context);
                      await controller.interact(kind);
                      if (mounted) {
                        _think(
                          friendText(
                            this.context,
                            switch (kind) {
                              FriendKind.clover =>
                                'Clover follows you to a sunny spot.',
                              FriendKind.sett =>
                                'Sett races over to fetch the ball.',
                              FriendKind.waybi =>
                                'Waybi spreads out a little travel map.',
                            },
                            switch (kind) {
                              FriendKind.clover => 'Clover 跟着你去晒太阳。',
                              FriendKind.sett => 'Sett 跑过去玩球啦。',
                              FriendKind.waybi => 'Waybi 摊开了小小的旅行地图。',
                            },
                          ),
                        );
                      }
                    },
                    icon: Icon(
                      kind == FriendKind.sett
                          ? Icons.sports_baseball_rounded
                          : kind == FriendKind.clover
                          ? Icons.wb_sunny_rounded
                          : Icons.map_outlined,
                    ),
                    label: Text(
                      friendText(
                        context,
                        kind == FriendKind.sett
                            ? 'Play fetch'
                            : kind == FriendKind.clover
                            ? 'Sit in the sunshine'
                            : 'Look at the map',
                        kind == FriendKind.sett
                            ? '一起玩球'
                            : kind == FriendKind.clover
                            ? '一起晒太阳'
                            : '一起看地图',
                      ),
                    ),
                  ),
                  if (controller.state.activeJourney == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _pack(kind);
                        },
                        icon: const Icon(Icons.backpack_rounded),
                        label: Text(
                          friendText(
                            context,
                            'Send $name exploring',
                            '让 $name 出门探索',
                          ),
                        ),
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

  Future<void> _pack(FriendKind initialTraveller) async {
    var traveller = initialTraveller;
    final locale = Localizations.localeOf(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: WwhColors.paper,
      builder: (sheetContext) => Localizations.override(
        context: sheetContext,
        locale: locale,
        child: StatefulBuilder(
          builder: (context, refresh) {
            final selected = controller.state.selectedItemIds;
            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      friendText(context, 'Pack a little trip', '准备一次小旅行'),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      friendText(
                        context,
                        'Bring up to two things, or travel light. Adventures last 20 minutes to 12 hours, even while the app is closed.',
                        '最多带两件东西，也可以轻装出门。旅行随机持续 20 分钟到 12 小时，关闭 App 后也会继续。',
                      ),
                      style: const TextStyle(
                        color: WwhColors.muted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SegmentedButton<FriendKind>(
                      segments: [
                        for (final kind in FriendKind.values)
                          ButtonSegment(
                            value: kind,
                            label: Text(friendName(kind)),
                          ),
                      ],
                      selected: {traveller},
                      onSelectionChanged: (value) =>
                          refresh(() => traveller = value.single),
                    ),
                    const SizedBox(height: 12),
                    PackingStatus(count: selected.length),
                    const SizedBox(height: 12),
                    for (final item in travelItems)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: selected.contains(item.id)
                              ? WwhColors.lime.withValues(alpha: .5)
                              : WwhColors.cream,
                          borderRadius: BorderRadius.circular(18),
                          child: ListTile(
                            key: ValueKey('pack-item-${item.id}'),
                            leading: TravelItemArt(item: item),
                            title: Text(travelItemName(context, item.id)),
                            subtitle: Text(travelItemNote(context, item.id)),
                            trailing: Icon(
                              selected.contains(item.id)
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined,
                            ),
                            onTap: () async {
                              final changed = await controller.toggleItem(
                                item.id,
                              );
                              if (context.mounted) {
                                refresh(() {});
                                if (!changed) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        friendText(
                                          context,
                                          'The bag is full. Remove an item first.',
                                          '背包满了，先拿出一件东西吧。',
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    FilledButton(
                      key: const ValueKey('send-friend-out'),
                      onPressed: () async {
                        await controller.startJourney(traveller: traveller);
                        if (context.mounted) Navigator.pop(context);
                        if (mounted) {
                          _think(
                            friendText(
                              this.context,
                              '${friendName(traveller)} slipped out for an adventure.',
                              '${friendName(traveller)} 背着小包出门啦。',
                            ),
                          );
                        }
                      },
                      child: Text(
                        friendText(
                          context,
                          'Send ${friendName(traveller)} out',
                          '让 ${friendName(traveller)} 出门',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
