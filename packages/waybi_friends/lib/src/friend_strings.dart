import 'package:flutter/widgets.dart';

import 'room_life.dart';
import 'models.dart';
import 'journey_engine.dart';

String friendText(BuildContext context, String english, String chinese) =>
    Localizations.maybeLocaleOf(context)?.languageCode == 'zh'
    ? chinese
    : english;

String roomCaption(
  BuildContext context,
  RoomMoment moment, {
  HomeScene scene = HomeScene.room,
}) {
  if (scene == HomeScene.garden) {
    return switch (moment) {
      RoomMoment.cloverWalking || RoomMoment.atWindow => friendText(
        context,
        'Clover has found a sunny patch in the garden.',
        'Clover 在花园里找到了一块暖暖的阳光。',
      ),
      RoomMoment.settling || RoomMoment.napping => friendText(
        context,
        'A little rest beside the flowers.',
        '在花丛旁休息一会儿。',
      ),
      RoomMoment.waking => friendText(
        context,
        'A little fresh air, together.',
        '一起吹吹风，看看花。',
      ),
      _ => _roomCaption(context, moment),
    };
  }
  return _roomCaption(context, moment);
}

String _roomCaption(BuildContext context, RoomMoment moment) =>
    switch (moment) {
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
      RoomMoment.playing => friendText(
        context,
        'A little playtime together.',
        '一起玩一会儿吧。',
      ),
    };

String memoryPlace(BuildContext context, JourneyMemory memory) =>
    memory.destinationName ??
    friendText(
      context,
      destinationById(memory.destinationId).name,
      destinationChineseName(memory.destinationId),
    );
String memoryTitle(BuildContext context, JourneyMemory memory) => friendText(
  context,
  memory.title,
  memory.titleZh ??
      '${friendName(memory.traveller)} 的${memoryPlace(context, memory)}小旅行',
);
String memoryStory(BuildContext context, JourneyMemory memory) => friendText(
  context,
  memory.story,
  memory.storyZh ??
      '${friendName(memory.traveller)} 去了${memoryPlace(context, memory)}，收集了一路的风景，也带回了一个小故事。',
);
String travelItemName(BuildContext context, String id) =>
    friendText(context, itemById(id).name, switch (id) {
      'camera' => '小相机',
      'snack' => '种子三明治',
      'umbrella' => '黄色小伞',
      'toy' => 'Sett 的球',
      _ => id,
    });
String travelItemNote(BuildContext context, String id) =>
    friendText(context, itemById(id).note, switch (id) {
      'camera' => '留意旅途中小小的美好。',
      'snack' => '有午餐的旅途更开心。',
      'umbrella' => '应对说变就变的天气。',
      'toy' => 'Sett 坚持说它会带来好运。',
      _ => '',
    });
String remainingJourneyTime(BuildContext context, Duration duration) {
  if (duration.inSeconds <= 0) {
    return friendText(context, 'almost home', '快到家了');
  }
  final minutes = (duration.inSeconds / 60).ceil();
  final hours = minutes ~/ 60, rest = minutes % 60;
  return hours == 0
      ? friendText(context, '$minutes min', '$minutes 分钟')
      : friendText(
          context,
          '$hours h${rest == 0 ? '' : ' $rest min'}',
          '$hours 小时${rest == 0 ? '' : ' $rest 分钟'}',
        );
}
