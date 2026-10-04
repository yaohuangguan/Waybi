import 'package:flutter/material.dart';

import 'friend_strings.dart';
import 'game_controller.dart';
import 'journey_engine.dart';
import 'models.dart';
import 'souvenir_art.dart';
import 'souvenirs.dart';
import 'theme.dart';

class SouvenirReward extends StatelessWidget {
  const SouvenirReward({super.key, required this.memory});
  final JourneyMemory memory;
  @override
  Widget build(BuildContext context) {
    final item = souvenirForMemory(memory);
    return Material(
      color: const Color(0xFFF3EBDD),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => showSouvenir(context, memory),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SouvenirIllustration(item: item, size: 72),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friendText(context, 'Waybi brought home', 'Waybi 带回了'),
                      style: const TextStyle(
                        color: WwhColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      friendText(context, item.name, item.chineseName),
                      style: const TextStyle(
                        color: WwhColors.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      friendText(
                        context,
                        'Tap to take a closer look',
                        '点开看看这件纪念品',
                      ),
                      style: const TextStyle(
                        color: WwhColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: WwhColors.moss),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showSouvenir(BuildContext context, JourneyMemory memory) async {
  final item = souvenirForMemory(memory);
  final destination = destinationById(memory.destinationId);
  final date = MaterialLocalizations.of(context)
      .formatMediumDate(memory.returnedAt.toLocal());
  await showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: WwhColors.paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  friendText(
                    context,
                    'A LITTLE SOMETHING TO KEEP',
                    '收藏一点旅途的惊喜',
                  ),
                  style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: .5,
                    color: WwhColors.muted,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1ECDD),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: SouvenirIllustration(item: item, size: 220),
                ),
                const SizedBox(height: 20),
                Text(
                  friendText(context, item.name, item.chineseName),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    color: WwhColors.ink,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  '${destination.name} · $date',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: WwhColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F2E5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    item.kind == SouvenirKind.letter
                        ? friendText(
                            context,
                            'Dear Clover and Sett,\n\n${memory.story}\n\nSee you by the window.\nLove, Waybi',
                            '亲爱的 Clover 和 Sett：\n\n${memory.story}\n\n回家后，窗边见。\n想你们的 Waybi',
                          )
                        : friendText(
                            context,
                            'Waybi found this little keepsake in ${destination.name}.\n\n${memory.story}',
                            'Waybi 在 ${destination.name} 收下了这件小纪念品。\n\n${memory.story}',
                          ),
                    style: const TextStyle(
                      color: WwhColors.ink,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(friendText(context, 'Keep it safe', '好好收起来')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class SouvenirCollectionPage extends StatelessWidget {
  const SouvenirCollectionPage({super.key, required this.controller});
  final GameController controller;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: WwhColors.cream,
    appBar: AppBar(title: Text(friendText(context, 'Souvenirs', '纪念品'))),
    body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final groups = <String, List<JourneyMemory>>{};
        for (final memory in controller.state.memories) {
          groups
              .putIfAbsent(souvenirForMemory(memory).id, () => [])
              .add(memory);
        }
        final collections = groups.values.toList(growable: false);
        if (collections.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SouvenirIllustration(item: souvenirItems.last, size: 150),
                  const SizedBox(height: 20),
                  Text(
                    friendText(
                      context,
                      'Room for little treasures.',
                      '给小宝物留点位置。',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 21,
                      color: WwhColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    friendText(
                      context,
                      'Postcards, maps and a few tasty surprises will collect here after Waybi comes home.',
                      '等 Waybi 回家，信、地图和好吃的小惊喜都会慢慢收进这里。',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: WwhColors.muted, height: 1.6),
                  ),
                ],
              ),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(18),
          itemCount: collections.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            mainAxisExtent: 214,
          ),
          itemBuilder: (context, index) {
            final copies = collections[index], memory = copies.first;
            final item = souvenirForMemory(memory);
            return Material(
              color: WwhColors.paper,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                key: ValueKey('souvenir-${item.id}'),
                borderRadius: BorderRadius.circular(22),
                onTap: () => showSouvenir(context, memory),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Expanded(
                        child: SouvenirIllustration(item: item, size: 120),
                      ),
                      Text(
                        friendText(context, item.name, item.chineseName),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: WwhColors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        friendText(
                          context,
                          '${copies.length} collected',
                          '已收藏 ${copies.length} 件',
                        ),
                        style: const TextStyle(
                          color: WwhColors.muted,
                          fontSize: 12,
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
    ),
  );
}
