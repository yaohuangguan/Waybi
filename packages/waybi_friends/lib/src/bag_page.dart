import 'package:flutter/material.dart';

import 'game_controller.dart';
import 'journey_engine.dart';
import 'theme.dart';

class BagPage extends StatelessWidget {
  const BagPage({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.state.selectedItemIds;
    final locked = controller.waybiAway;

    return ColoredBox(
      color: WwhColors.cream,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Little bag',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              locked ? 'Waybi took this bag along for the journey.' : 'Pick up to two things. Tiny choices can bend a journey in different directions.',
              style: const TextStyle(
                color: WwhColors.muted,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFE9EFD8),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0x143A5729)),
              ),
              child: Row(
                children: [
                  Image.asset(
                    'packages/waybi_friends/assets/characters/waybi.png',
                    width: 74,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      selected.isEmpty
                          ? 'The bag is almost empty. That is allowed.'
                          : 'Packed: ${selected.map((id) => itemById(id).emoji).join('  ')}',
                      style: const TextStyle(
                        color: WwhColors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: travelItems.length,
                separatorBuilder: (_, _) => const SizedBox(height: 11),
                itemBuilder: (context, index) {
                  final item = travelItems[index];
                  final isSelected = selected.contains(item.id);
                  return Opacity(
                    opacity: locked ? .66 : 1,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: locked
                          ? null
                          : () => controller.toggleItem(item.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? WwhColors.lime.withValues(alpha: .5)
                              : WwhColors.paper,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? WwhColors.moss.withValues(alpha: .28)
                                : const Color(0x1423351D),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: WwhColors.cream,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Center(
                                child: Text(
                                  item.emoji,
                                  style: const TextStyle(fontSize: 28),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: const TextStyle(
                                      color: WwhColors.ink,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
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
                            Icon(
                              isSelected
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined,
                              color: isSelected
                                  ? WwhColors.moss
                                  : const Color(0x4023351D),
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
      ),
    );
  }
}
