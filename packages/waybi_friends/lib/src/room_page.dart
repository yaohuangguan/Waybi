import 'dart:math';

import 'package:flutter/material.dart';

import 'game_controller.dart';
import 'friend_strings.dart';
import 'living_room_scene.dart';
import 'journey_engine.dart';
import 'packing_status.dart';
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
  final bool showHeader;
  final bool showPrototypeControls;

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  String? ambient;
  DateTime? thoughtUntil;

  void refreshAmbient(String value) {
    if (!mounted) return;
    setState(() {
      ambient = value;
      thoughtUntil = widget.controller.clock().add(const Duration(seconds: 4));
    });
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.controller.state.activeJourney;
    final now = widget.controller.clock();
    final greeting = now.hour < 12
        ? friendText(context, 'Good morning', '早上好')
        : now.hour < 18
        ? friendText(context, 'Good afternoon', '下午好')
        : friendText(context, 'Good evening', '晚上好');

    return ColoredBox(
      color: WwhColors.cream,
      child: Column(
        children: [
          if (widget.showHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greeting,
                          style: const TextStyle(
                            color: WwhColors.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          friendText(context, "Waybi's Way Home", '伙伴的小屋'),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: WwhColors.paper,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: const Color(0x1823351D)),
                    ),
                    child: const Icon(
                      Icons.wb_sunny_rounded,
                      color: Color(0xFFD99A44),
                      size: 21,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: Column(
                children: [
                  Expanded(
                    child: LivingRoomScene(
                      life: widget.controller.roomLife,
                      clock: widget.controller.clock,
                      thought: ambient,
                      thoughtUntil: thoughtUntil,
                      waybiAway: widget.controller.waybiAway,
                      onWaybiTap: () => refreshAmbient(
                        waybiHomeLines[Random().nextInt(waybiHomeLines.length)],
                      ),
                      onCloverTap: () => refreshAmbient(
                        cloverLines[Random().nextInt(cloverLines.length)],
                      ),
                      onSettTap: () => refreshAmbient(
                        settLines[Random().nextInt(settLines.length)],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (active == null)
                    _HomeJourneyPrompt(onPack: () => _openPackingSheet(context))
                  else
                    _AwayCard(
                      returnAt: active.returnAt,
                      clock: widget.controller.clock,
                      onBringHome: widget.showPrototypeControls
                          ? widget.controller.bringWaybiHomeForPrototype
                          : null,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPackingSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WwhColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final selected = widget.controller.state.selectedItemIds;
            return SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0x2223351D),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Pack a little trip',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        'Bring up to two things, or let Waybi travel light. Each item adds a little something to the story.',
                        style: TextStyle(color: WwhColors.muted, height: 1.45),
                      ),
                      const SizedBox(height: 8),
                      PackingStatus(count: selected.length),
                      const SizedBox(height: 20),
                      ...travelItems.map((item) {
                        final isSelected = selected.contains(item.id);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: InkWell(
                            key: ValueKey('pack-item-${item.id}'),
                            borderRadius: BorderRadius.circular(18),
                            onTap: () async {
                              final changed = await widget.controller
                                  .toggleItem(item.id);
                              if (context.mounted) {
                                setSheetState(() {});
                                if (!changed) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'The bag is full. Remove an item first.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.all(15),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? WwhColors.lime.withValues(alpha: .48)
                                    : const Color(0xFFF7F5ED),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isSelected
                                      ? WwhColors.moss.withValues(alpha: .34)
                                      : const Color(0x1023351D),
                                ),
                              ),
                              child: Row(
                                children: [
                                  TravelItemArt(item: item),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: const TextStyle(
                                            color: WwhColors.ink,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          item.note,
                                          style: const TextStyle(
                                            color: WwhColors.muted,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 150),
                                    child: isSelected
                                        ? const Icon(
                                            Icons.check_circle_rounded,
                                            key: ValueKey('checked'),
                                            color: WwhColors.moss,
                                          )
                                        : const Icon(
                                            Icons.circle_outlined,
                                            key: ValueKey('empty'),
                                            color: Color(0x4023351D),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () async {
                            await widget.controller.startJourney();
                            if (context.mounted) Navigator.pop(context);
                            refreshAmbient(
                              'Waybi slipped out quietly. Sett noticed immediately.',
                            );
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: WwhColors.ink,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 17),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                          child: Text(
                            selected.isEmpty
                                ? 'Let Waybi wander'
                                : 'Send Waybi out',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (widget.showPrototypeControls)
                        const Center(
                          child: Text(
                            'Prototype journeys take 2–8 minutes.',
                            style: TextStyle(
                              color: WwhColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _HomeJourneyPrompt extends StatelessWidget {
  const _HomeJourneyPrompt({required this.onPack});

  final VoidCallback onPack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
      decoration: BoxDecoration(
        color: WwhColors.paper,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x1423351D)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friendText(context, 'Waybi is home.', 'Waybi 在家里。'),
                  style: TextStyle(
                    color: WwhColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  friendText(
                    context,
                    'Maybe pack something for a little journey?',
                    '给下一次小旅行准备点什么？',
                  ),
                  style: TextStyle(color: WwhColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: onPack,
            style: FilledButton.styleFrom(
              backgroundColor: WwhColors.lime,
              foregroundColor: WwhColors.ink,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            ),
            child: Text(
              friendText(context, 'Pack', '打包'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _AwayCard extends StatelessWidget {
  const _AwayCard({
    required this.returnAt,
    required this.onBringHome,
    required this.clock,
  });

  final DateTime returnAt;
  final DateTime Function() clock;
  final Future<void> Function()? onBringHome;

  String _timeLeft(BuildContext context) {
    final remaining = returnAt.difference(clock());
    if (remaining.isNegative) return friendText(context, 'almost home', '快到家了');
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 15, 14, 15),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF3DE),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x183A5729)),
      ),
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: WwhColors.paper,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text('🗺️', style: TextStyle(fontSize: 23)),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friendText(context, 'Waybi is out exploring', 'Waybi 正在外面探索'),
                  style: TextStyle(
                    color: WwhColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  friendText(
                    context,
                    'Expected home in ${_timeLeft(context)}',
                    '预计 ${_timeLeft(context)} 后到家',
                  ),
                  style: const TextStyle(color: WwhColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          if (onBringHome != null)
            TextButton(
              onPressed: onBringHome,
              child: const Text(
                'bring home',
                style: TextStyle(fontSize: 11, color: WwhColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}
