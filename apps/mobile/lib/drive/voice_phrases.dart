import 'package:flutter/foundation.dart';

/// One recordable phrase in a custom voice pack.
///
/// [en] / [zh] list every spelling the guidance code produces for the
/// phrase; the first entry is the prompt the user reads aloud when recording
/// and the wording used when a sentence is built from parts. An empty list
/// means the phrase does not exist in that language (Chinese has no "onto",
/// English has no "位于"), so it is not offered for recording there.
///
/// Phrase ids are stored on devices and inside shared voice packs: an id
/// must never change meaning. Add a new id for new wording.
@immutable
class VoicePhrase {
  const VoicePhrase(
    this.id,
    this.group,
    this.en,
    this.zh, {
    this.metres,
    this.keepCase = false,
    this.standalone = true,
  });
  final String id;
  final VoicePhraseGroup group;
  final List<String> en;
  final List<String> zh;

  /// Distance phrases only: the distance this clip announces.
  final int? metres;

  /// English wording that keeps its capital letter mid-sentence ("Monday",
  /// "T2 transit lane").
  final bool keepCase;

  /// False for glue words ("onto", "有", "metres") that only make sense
  /// inside a prompt built from parts; free-form messages never match them.
  final bool standalone;

  List<String> texts(String language) => language == 'zh' ? zh : en;
  String prompt(String language) => texts(language).first;

  /// True when this phrase is spoken in [language] at all.
  bool availableIn(String language) => texts(language).isNotEmpty;
}

/// Sections of the recording page, in display order.
enum VoicePhraseGroup {
  distance,
  maneuver,
  connector,
  camera,
  roadAlert,
  trip,
  arrival,
}

/// Distances with their own "In 300 metres" clip. Spoken distances snap to
/// one of these only when close; otherwise the number is read by the
/// standard voice between "In" and "metres".
const voiceDistances = [
  50,
  100,
  200,
  300,
  400,
  500,
  800,
  1000,
  1200,
  1500,
  2000,
];

String _enDistance(int metres) =>
    metres >= 1000 ? 'In ${_km(metres)} kilometres' : 'In $metres metres';
String _zhDistance(int metres) =>
    metres >= 1000 ? '${_km(metres)} 公里后' : '$metres 米后';
String _km(int metres) => metres % 1000 == 0
    ? '${metres ~/ 1000}'
    : (metres / 1000).toStringAsFixed(1);

const _weekdaysEn = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _weekdaysZh = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/// Ids of phrases the prompt builders compose sentences from.
abstract final class VoicePhraseId {
  static String distance(int metres) => 'in_$metres';
  static const distanceIn = 'dist_in';
  static const distanceMetres = 'dist_metres';
  static const distanceKilometres = 'dist_kilometres';

  static const turnLeft = 'turn_left';
  static const turnRight = 'turn_right';
  static const bearLeft = 'bear_left';
  static const bearRight = 'bear_right';
  static const sharpLeft = 'sharp_left';
  static const sharpRight = 'sharp_right';
  static const keepLeft = 'keep_left';
  static const keepRight = 'keep_right';
  static const continueStraight = 'continue_straight';
  static const continueRoute = 'continue_route';
  static const uturn = 'uturn';
  static String roundaboutExit(int exit) => 'roundabout_exit_$exit';
  static const roundabout = 'roundabout';
  static const exitRoundabout = 'exit_roundabout';
  static const exitLeft = 'exit_left';
  static const exitRight = 'exit_right';
  static const exit = 'exit';
  static const ramp = 'ramp';
  static const merge = 'merge';
  static const ferry = 'ferry';
  static const depart = 'depart';

  static const onto = 'conn_onto';
  static const toward = 'conn_toward';
  static const on = 'conn_on';
  static const locatedOn = 'conn_located';
  static const thereIs = 'conn_there_is';

  static const cameraSpeed = 'camera_speed';
  static const cameraAverage = 'camera_average';
  static const cameraRedLightSpeed = 'camera_red_light_speed';
  static const cameraRedLight = 'camera_red_light';
  static const cameraBusLane = 'camera_bus_lane';
  static const cameraSafety = 'camera_safety';

  static const ahead = 'ahead';
  static const laneBus = 'lane_bus';
  static const laneT2 = 'lane_t2';
  static const laneT3 = 'lane_t3';
  static const laneTruck = 'lane_truck';
  static const hoursUnconfirmed = 'schedule_unconfirmed';
  static const allDayEveryDay = 'schedule_always';
  static const allDay = 'schedule_all_day';
  static const everyDay = 'day_every';
  static const weekdays = 'day_weekdays';

  /// [weekday] is 1 (Monday) to 7 (Sunday).
  static String day(int weekday) => 'day_$weekday';
  static const timeTo = 'time_to';
  static const timeHour = 'time_hour';
  static const timeMinute = 'time_minute';
  static const laneCheckSigns = 'lane_check_signs';
  static const laneNoCars = 'lane_no_cars';
  static const laneCheckOccupancy = 'lane_check_occupancy';
  static const laneTurningLeft = 'lane_turning_left';
  static const laneStayGeneral = 'lane_stay_general';

  static const transitTripStarted = 'trip_transit_started';

  static const arriveAtDestination = 'arrive_at_destination';
  static const arrived = 'arrived';
  static const wellDone = 'well_done';
}

/// Every fixed piece of wording the app speaks, matched against the prompt
/// builders in `voice_prompts.dart` and, for free-form messages, by
/// `planCustomVoice`.
final List<VoicePhrase> customVoicePhrases = List.unmodifiable([
  for (final metres in voiceDistances)
    VoicePhrase(
      VoicePhraseId.distance(metres),
      VoicePhraseGroup.distance,
      [_enDistance(metres)],
      [_zhDistance(metres)],
      metres: metres,
    ),
  const VoicePhrase(
    VoicePhraseId.distanceIn,
    VoicePhraseGroup.distance,
    ['In'],
    [],
    standalone: false,
  ),
  const VoicePhrase(
    VoicePhraseId.distanceMetres,
    VoicePhraseGroup.distance,
    ['metres'],
    ['米后'],
    standalone: false,
  ),
  const VoicePhrase(
    VoicePhraseId.distanceKilometres,
    VoicePhraseGroup.distance,
    ['kilometres'],
    ['公里后'],
    standalone: false,
  ),
  const VoicePhrase(
    VoicePhraseId.turnLeft,
    VoicePhraseGroup.maneuver,
    ['Turn left'],
    ['左转'],
  ),
  const VoicePhrase(
    VoicePhraseId.turnRight,
    VoicePhraseGroup.maneuver,
    ['Turn right'],
    ['右转'],
  ),
  const VoicePhrase(
    VoicePhraseId.bearLeft,
    VoicePhraseGroup.maneuver,
    ['Bear left', 'Turn slight left', 'Slight left'],
    ['向左前方行驶'],
  ),
  const VoicePhrase(
    VoicePhraseId.bearRight,
    VoicePhraseGroup.maneuver,
    ['Bear right', 'Turn slight right', 'Slight right'],
    ['向右前方行驶'],
  ),
  const VoicePhrase(
    VoicePhraseId.sharpLeft,
    VoicePhraseGroup.maneuver,
    ['Turn sharp left', 'Sharp left'],
    ['向左急转'],
  ),
  const VoicePhrase(
    VoicePhraseId.sharpRight,
    VoicePhraseGroup.maneuver,
    ['Turn sharp right', 'Sharp right'],
    ['向右急转'],
  ),
  const VoicePhrase(
    VoicePhraseId.keepLeft,
    VoicePhraseGroup.maneuver,
    ['Keep left'],
    ['靠左行驶'],
  ),
  const VoicePhrase(
    VoicePhraseId.keepRight,
    VoicePhraseGroup.maneuver,
    ['Keep right'],
    ['靠右行驶'],
  ),
  const VoicePhrase(
    VoicePhraseId.continueStraight,
    VoicePhraseGroup.maneuver,
    ['Continue straight'],
    ['继续直行'],
  ),
  const VoicePhrase(
    VoicePhraseId.continueRoute,
    VoicePhraseGroup.maneuver,
    ['Continue on route'],
    ['沿路线继续行驶'],
  ),
  const VoicePhrase(
    VoicePhraseId.uturn,
    VoicePhraseGroup.maneuver,
    ['Make a U-turn'],
    ['掉头'],
  ),
  for (var exit = 1; exit <= 4; exit++)
    VoicePhrase(
      VoicePhraseId.roundaboutExit(exit),
      VoicePhraseGroup.maneuver,
      ['At the roundabout, take exit $exit'],
      ['进入环岛，从第 $exit 个出口驶出'],
    ),
  const VoicePhrase(
    VoicePhraseId.roundabout,
    VoicePhraseGroup.maneuver,
    ['Enter the roundabout'],
    ['驶入环岛'],
  ),
  const VoicePhrase(
    VoicePhraseId.exitRoundabout,
    VoicePhraseGroup.maneuver,
    ['Exit the roundabout'],
    ['驶出环岛'],
  ),
  const VoicePhrase(
    VoicePhraseId.exitLeft,
    VoicePhraseGroup.maneuver,
    ['Take the left exit'],
    ['从左侧出口驶出'],
  ),
  const VoicePhrase(
    VoicePhraseId.exitRight,
    VoicePhraseGroup.maneuver,
    ['Take the right exit'],
    ['从右侧出口驶出'],
  ),
  const VoicePhrase(
    VoicePhraseId.exit,
    VoicePhraseGroup.maneuver,
    ['Take the exit'],
    ['从出口驶出'],
  ),
  const VoicePhrase(
    VoicePhraseId.ramp,
    VoicePhraseGroup.maneuver,
    ['Take the ramp'],
    ['驶入匝道'],
  ),
  const VoicePhrase(
    VoicePhraseId.merge,
    VoicePhraseGroup.maneuver,
    ['Merge ahead'],
    ['汇入前方道路'],
  ),
  const VoicePhrase(
    VoicePhraseId.ferry,
    VoicePhraseGroup.maneuver,
    ['Take the ferry'],
    ['搭乘渡轮'],
  ),
  const VoicePhrase(
    VoicePhraseId.depart,
    VoicePhraseGroup.maneuver,
    ['Head out'],
    ['出发'],
  ),
  const VoicePhrase(
    VoicePhraseId.onto,
    VoicePhraseGroup.connector,
    ['onto'],
    [],
    standalone: false,
  ),
  const VoicePhrase(
    VoicePhraseId.toward,
    VoicePhraseGroup.connector,
    ['toward'],
    ['驶向'],
    standalone: false,
  ),
  const VoicePhrase(
    VoicePhraseId.on,
    VoicePhraseGroup.connector,
    ['on'],
    [],
    standalone: false,
  ),
  const VoicePhrase(VoicePhraseId.locatedOn, VoicePhraseGroup.connector, [], [
    '位于',
  ], standalone: false),
  const VoicePhrase(VoicePhraseId.thereIs, VoicePhraseGroup.connector, [], [
    '有',
  ], standalone: false),
  const VoicePhrase(
    VoicePhraseId.cameraSpeed,
    VoicePhraseGroup.camera,
    ['Speed camera', 'Fixed speed camera'],
    ['定点测速摄像头'],
  ),
  const VoicePhrase(
    VoicePhraseId.cameraAverage,
    VoicePhraseGroup.camera,
    ['Average-speed camera'],
    ['区间测速摄像头'],
  ),
  const VoicePhrase(
    VoicePhraseId.cameraRedLightSpeed,
    VoicePhraseGroup.camera,
    ['Red-light + speed camera'],
    ['红灯及测速摄像头'],
  ),
  const VoicePhrase(
    VoicePhraseId.cameraRedLight,
    VoicePhraseGroup.camera,
    ['Red-light camera'],
    ['红灯摄像头'],
  ),
  const VoicePhrase(
    VoicePhraseId.cameraBusLane,
    VoicePhraseGroup.camera,
    ['Bus-lane camera'],
    ['专用车道摄像头'],
  ),
  const VoicePhrase(
    VoicePhraseId.cameraSafety,
    VoicePhraseGroup.camera,
    ['Safety camera'],
    ['安全摄像头'],
  ),
  const VoicePhrase(
    VoicePhraseId.ahead,
    VoicePhraseGroup.roadAlert,
    ['Ahead'],
    ['前方'],
  ),
  const VoicePhrase(
    VoicePhraseId.laneBus,
    VoicePhraseGroup.roadAlert,
    ['Bus lane'],
    ['公交车道'],
  ),
  const VoicePhrase(
    VoicePhraseId.laneT2,
    VoicePhraseGroup.roadAlert,
    ['T2 transit lane'],
    ['T2 专用车道'],
    keepCase: true,
  ),
  const VoicePhrase(
    VoicePhraseId.laneT3,
    VoicePhraseGroup.roadAlert,
    ['T3 transit lane'],
    ['T3 专用车道'],
    keepCase: true,
  ),
  const VoicePhrase(
    VoicePhraseId.laneTruck,
    VoicePhraseGroup.roadAlert,
    ['Truck lane'],
    ['货车专用车道'],
  ),
  const VoicePhrase(
    VoicePhraseId.hoursUnconfirmed,
    VoicePhraseGroup.roadAlert,
    ['Hours unconfirmed · check signs'],
    ['时段未确认，请查看路牌'],
  ),
  const VoicePhrase(
    VoicePhraseId.allDayEveryDay,
    VoicePhraseGroup.roadAlert,
    ['Active 24 hours, every day'],
    ['每天全天生效'],
  ),
  const VoicePhrase(
    VoicePhraseId.allDay,
    VoicePhraseGroup.roadAlert,
    ['24 hours'],
    ['全天生效'],
  ),
  const VoicePhrase(
    VoicePhraseId.everyDay,
    VoicePhraseGroup.roadAlert,
    ['Every day'],
    ['每天'],
  ),
  const VoicePhrase(
    VoicePhraseId.weekdays,
    VoicePhraseGroup.roadAlert,
    ['Monday to Friday'],
    ['周一至周五'],
    keepCase: true,
  ),
  for (var day = 1; day <= 7; day++)
    VoicePhrase(
      VoicePhraseId.day(day),
      VoicePhraseGroup.roadAlert,
      [_weekdaysEn[day - 1]],
      [_weekdaysZh[day - 1]],
      keepCase: true,
    ),
  const VoicePhrase(
    VoicePhraseId.timeTo,
    VoicePhraseGroup.roadAlert,
    ['to'],
    ['至'],
    standalone: false,
  ),
  const VoicePhrase(VoicePhraseId.timeHour, VoicePhraseGroup.roadAlert, [], [
    '点',
  ], standalone: false),
  const VoicePhrase(VoicePhraseId.timeMinute, VoicePhraseGroup.roadAlert, [], [
    '分',
  ], standalone: false),
  const VoicePhrase(
    VoicePhraseId.laneCheckSigns,
    VoicePhraseGroup.roadAlert,
    ['Check lane signs and operating hours'],
    ['请查看专用车道标志和生效时段'],
  ),
  const VoicePhrase(
    VoicePhraseId.laneNoCars,
    VoicePhraseGroup.roadAlert,
    ['No access for ordinary cars · choose another route'],
    ['此路段禁止普通汽车通行，请选择其他路线'],
  ),
  const VoicePhrase(
    VoicePhraseId.laneCheckOccupancy,
    VoicePhraseGroup.roadAlert,
    ['Check occupancy requirements or stay in a general lane'],
    ['请确认人数要求，否则保持普通车道'],
  ),
  const VoicePhrase(
    VoicePhraseId.laneTurningLeft,
    VoicePhraseGroup.roadAlert,
    ['Turning left · avoid entering the bus lane too early'],
    ['准备左转，请勿过早并入公交车道'],
  ),
  const VoicePhrase(
    VoicePhraseId.laneStayGeneral,
    VoicePhraseGroup.roadAlert,
    ['Stay in a general traffic lane'],
    ['请保持普通车道'],
  ),
  const VoicePhrase(
    VoicePhraseId.transitTripStarted,
    VoicePhraseGroup.trip,
    ['Transit trip started. Follow the itinerary.'],
    ['公交行程已开始，请按行程出行。'],
  ),
  const VoicePhrase(
    VoicePhraseId.arriveAtDestination,
    VoicePhraseGroup.arrival,
    ['Arrive at destination'],
    ['到达目的地'],
  ),
  const VoicePhrase(
    VoicePhraseId.arrived,
    VoicePhraseGroup.arrival,
    ['You have arrived'],
    ['已到达目的地'],
  ),
  const VoicePhrase(
    VoicePhraseId.wellDone,
    VoicePhraseGroup.arrival,
    ['Well done!'],
    ['这段旅程辛苦啦！'],
  ),
]);

final Map<String, VoicePhrase> _phrasesById = {
  for (final phrase in customVoicePhrases) phrase.id: phrase,
};

VoicePhrase? customVoicePhrase(String id) => _phrasesById[id];

/// The phrases offered for recording in [language], in display order.
List<VoicePhrase> voicePhrasesFor(String language, [VoicePhraseGroup? group]) =>
    [
      for (final phrase in customVoicePhrases)
        if (phrase.availableIn(language) &&
            (group == null || phrase.group == group))
          phrase,
    ];
