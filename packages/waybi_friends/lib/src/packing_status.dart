import 'package:flutter/material.dart';

import 'game_controller.dart';
import 'theme.dart';

class PackingStatus extends StatelessWidget {
  const PackingStatus({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Text(
    '$count / ${GameController.bagCapacity} packed · '
    '${count >= GameController.bagCapacity ? 'Remove an item to swap it.' : 'One item or an empty bag is welcome.'}',
    style: const TextStyle(color: WwhColors.muted, fontSize: 13, height: 1.45),
  );
}
