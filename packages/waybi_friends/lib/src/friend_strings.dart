import 'package:flutter/widgets.dart';

import 'room_life.dart';

String friendText(BuildContext context, String english, String chinese) =>
    Localizations.maybeLocaleOf(context)?.languageCode == 'zh'
    ? chinese
    : english;

String roomCaption(BuildContext context, RoomMoment moment) => switch (moment) {
  RoomMoment.waking => friendText(
    context,
    'A little morning, together.',
    '小小的一天，从一起待着开始。',
  ),
  RoomMoment.cloverWalking => friendText(
    context,
    'Clover has found a sunny spot.',
    'Clover 想去窗边晒晒太阳。',
  ),
  RoomMoment.atWindow => friendText(
    context,
    'Clover is watching the world go by.',
    'Clover 正在窗边看外面的世界。',
  ),
  RoomMoment.settFollowing => friendText(
    context,
    'Sett wants to see what Clover sees.',
    'Sett 跑过去，也想看看 Clover 在看什么。',
  ),
  RoomMoment.settling => friendText(
    context,
    'The sofa is calling Clover back.',
    'Clover 又想念柔软的沙发了。',
  ),
  RoomMoment.napping => friendText(
    context,
    'A small nap. Sett is keeping watch.',
    'Clover 打个盹，Sett 在旁边守着。',
  ),
  RoomMoment.exploring => friendText(
    context,
    'Sett has somewhere very important to be.',
    'Sett 又发现了一个值得跑过去的地方。',
  ),
  RoomMoment.departing => friendText(
    context,
    'Bag packed. A little adventure awaits.',
    '背好小包，Waybi 要出门探索了。',
  ),
  RoomMoment.returning => friendText(
    context,
    'Waybi is home, with a story to tell.',
    'Waybi 回来了，还带着一个小故事。',
  ),
  RoomMoment.waybiAway => friendText(
    context,
    'Waybi is exploring. Home is still here.',
    'Waybi 去探索了，家里还是暖暖的。',
  ),
};
