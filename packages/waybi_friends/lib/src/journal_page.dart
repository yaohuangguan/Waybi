import 'package:flutter/material.dart';

import 'game_controller.dart';
import 'postcard_dialog.dart';
import 'theme.dart';
import 'friend_strings.dart';
import 'souvenir_art.dart';
import 'souvenir_collection.dart';
import 'souvenirs.dart';

class JournalPage extends StatelessWidget {
  const JournalPage({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final memories = controller.state.memories;

    return ColoredBox(
      color: WwhColors.cream,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    friendText(context, 'Journal', '旅行册'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          SouvenirCollectionPage(controller: controller),
                    ),
                  ),
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: Text(friendText(context, 'Souvenirs', '纪念品')),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              memories.isEmpty
                  ? friendText(
                      context,
                      'Little journeys will collect here.',
                      '小旅行的记忆会收藏在这里。',
                    )
                  : friendText(
                      context,
                      '${memories.length} journeys so far.',
                      '已经收藏 ${memories.length} 段旅行。',
                    ),
              style: const TextStyle(color: WwhColors.muted, fontSize: 14),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: memories.isEmpty
                  ? const _EmptyJournal()
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 18),
                      itemCount: memories.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 13),
                      itemBuilder: (context, index) {
                        final memory = memories[index];
                        final destinationName = memoryPlace(context, memory);
                        return InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: () => showPostcardDialog(context, memory),
                          child: Container(
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: WwhColors.paper,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: const Color(0x1423351D),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 78,
                                  height: 82,
                                  decoration: BoxDecoration(
                                    color: _toneFor(memory.destinationId),
                                    borderRadius: BorderRadius.circular(17),
                                  ),
                                  child: Center(
                                    child: SouvenirIllustration(
                                      item: souvenirForMemory(memory),
                                      size: 72,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        destinationName,
                                        style: const TextStyle(
                                          color: WwhColors.ink,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        memoryStory(context, memory),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: WwhColors.muted,
                                          height: 1.35,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 9),
                                      Row(
                                        children: [
                                          const Padding(
                                            padding: EdgeInsets.only(right: 5),
                                            child: Icon(
                                              Icons.card_giftcard_rounded,
                                              size: 16,
                                              color: WwhColors.moss,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              friendText(
                                                context,
                                                souvenirForMemory(memory).name,
                                                souvenirForMemory(memory)
                                                    .chineseName,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: WwhColors.ink,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: WwhColors.muted,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Color _toneFor(String id) {
    switch (id) {
      case 'mission_bay':
      case 'takapuna':
        return const Color(0xFFD7EDF0);
      case 'piha':
        return const Color(0xFFEAD5C6);
      case 'waiheke':
        return const Color(0xFFDDEAD5);
      default:
        return const Color(0xFFE8EBCF);
    }
  }
}

class _EmptyJournal extends StatelessWidget {
  const _EmptyJournal();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: const BoxDecoration(
                color: Color(0xFFECE5D5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_stories_rounded,
                size: 48,
                color: WwhColors.moss,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              friendText(context, 'Nothing here yet.', '还没有旅行记忆。'),
              style: TextStyle(
                color: WwhColors.ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            SizedBox(
              width: 250,
              child: Text(
                friendText(
                  context,
                  'Pack a small bag and see what comes home. Real arrivals bring keepsakes too.',
                  '给伙伴准备小背包，看看会带什么回来。完成真实导航后也会收下纪念品。',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: WwhColors.muted, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
