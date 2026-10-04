import 'package:flutter/material.dart';

import 'game_controller.dart';
import 'journey_engine.dart';
import 'postcard_dialog.dart';
import 'theme.dart';

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
            Text('Journal', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text(
              memories.isEmpty
                  ? 'Little journeys will collect here.'
                  : '${memories.length} little ${memories.length == 1 ? 'journey' : 'journeys'} so far.',
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
                        final destination = destinationById(
                          memory.destinationId,
                        );
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
                                    color: _toneFor(destination.id),
                                    borderRadius: BorderRadius.circular(17),
                                  ),
                                  child: Stack(
                                    children: [
                                      Center(
                                        child: Text(
                                          destination.emoji,
                                          style: const TextStyle(fontSize: 34),
                                        ),
                                      ),
                                      Positioned(
                                        left: -2,
                                        bottom: -7,
                                        child: Image.asset(
                                          'packages/waybi_friends/assets/characters/waybi.png',
                                          width: 48,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        destination.name,
                                        style: const TextStyle(
                                          color: WwhColors.ink,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        memory.story,
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
                                          const Text(
                                            '🎒 ',
                                            style: TextStyle(fontSize: 13),
                                          ),
                                          Expanded(
                                            child: Text(
                                              memory.souvenir,
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
            const Text(
              'Nothing here yet.',
              style: TextStyle(
                color: WwhColors.ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            const SizedBox(
              width: 250,
              child: Text(
                'Pack Waybi a small bag and see what comes home.',
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
