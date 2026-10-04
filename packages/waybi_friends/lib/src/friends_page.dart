import 'package:flutter/material.dart';

import 'app.dart';
import 'character_rig.dart';
import 'room_life.dart';
import 'theme.dart';

class FriendsPage extends StatelessWidget {
  const FriendsPage({super.key, this.language = 'en'});
  final String language;
  @override
  Widget build(BuildContext context) => Localizations.override(
    context: context,
    locale: Locale(language == 'zh' ? 'zh' : 'en'),
    child: Theme(
      data: buildWaybiTheme(),
      child: const GameShell(embedded: true),
    ),
  );
}

class FriendsEntry extends StatelessWidget {
  const FriendsEntry({super.key, this.chinese = false, this.onOpen});
  final bool chinese;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: InkWell(
        key: const ValueKey('waybi-friends-entry'),
        borderRadius: BorderRadius.circular(18),
        onTap:
            onOpen ??
            () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FriendsPage(language: chinese ? 'zh' : 'en'),
              ),
            ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: CustomPaint(
                  painter: CharacterRig(
                    pose: const FriendPose(
                      kind: FriendKind.waybi,
                      position: RoomLife.waybiHome,
                    ),
                    seconds: 1,
                    reducedMotion: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Waybi & Friends',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      chinese
                          ? '去看看 Waybi、Clover 和 Sett'
                          : 'Visit Waybi, Clover & Sett',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
