import 'package:flutter/material.dart';

import 'game_controller.dart';
import 'friend_strings.dart';
import 'theme.dart';

class PackingStatus extends StatelessWidget {
  const PackingStatus({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Text(
    friendText(
      context,
      '$count / ${GameController.bagCapacity} packed · '
          '${count >= GameController.bagCapacity ? 'Remove an item to swap it.' : 'One item or an empty bag is welcome.'}',
      '已装 $count / ${GameController.bagCapacity} 件 · '
          '${count >= GameController.bagCapacity ? '先拿出一件，就可以换一件。' : '带一件或空背包出门都可以。'}',
    ),
    style: const TextStyle(color: WwhColors.muted, fontSize: 13, height: 1.45),
  );
}
