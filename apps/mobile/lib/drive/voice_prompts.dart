import '../domain/map_layer_settings.dart';
import '../domain/route_option.dart';
import '../domain/transit_lane.dart';
import 'navigation_language.dart';
import 'voice_phrases.dart';
import 'voice_utterance.dart';

/// Builders for every prompt Waybi speaks. Each returns the prompt as parts
/// (fixed phrases a member can record, plus dynamic road names and numbers)
/// together with the plain sentence the standard voice reads.
///
/// [language] is the navigation language, 'en' or 'zh'.
abstract final class VoicePrompts {
  /// A maneuver on its own: "Turn left onto Queen Street".
  ///
  /// The standard voice keeps the routing engine's own sentence when there
  /// is one ("Take exit 414 towards Albany"); a custom voice speaks the
  /// maneuver from its structured fields so every fixed word is a phrase.
  static VoiceUtterance routeStep(RouteStepInfo? step, String language) {
    final text = routeStepInstruction(step, language);
    if (step != null &&
        step.maneuverType.trim().isEmpty &&
        step.maneuverModifier.trim().isEmpty &&
        step.instruction.trim().isNotEmpty) {
      // Nothing structured to build from: match phrases in the sentence.
      return VoiceUtterance.freeform(text, language);
    }
    return VoiceUtterance(language, routeStepParts(step, language), text: text);
  }

  /// A turn prompt [metres] before the maneuver: "In 300 m, Turn left onto
  /// Queen Street" / "300 米后，左转，驶向 Queen Street". Without [metres] the
  /// maneuver itself ("Turn left").
  static VoiceUtterance turn(
    RouteStepInfo step,
    String language, {
    num? metres,
  }) {
    final maneuver = routeStep(step, language);
    if (metres == null) return maneuver;
    final zh = language == 'zh';
    final distance = navigationMetres(metres, language);
    final text = zh
        ? '$distance后，${maneuver.text}'
        : 'In $distance, ${maneuver.text}';
    if (!maneuver.structured) return VoiceUtterance.freeform(text, language);
    return VoiceUtterance(language, [
      DistancePart(metres),
      PausePart(zh ? '，' : ','),
      ...maneuver.parts,
    ], text: text);
  }

  /// "In 300 metres, speed camera on Queen Street." /
  /// "300 米后有定点测速摄像头，位于 Queen Street。"
  static VoiceUtterance camera({
    required num metres,
    required String cameraType,
    required String roadName,
    required String language,
  }) {
    final zh = language == 'zh';
    final camera = cameraPhrase(CameraKindLabel.fromType(cameraType));
    final road = roadName.trim();
    return VoiceUtterance(language, [
      DistancePart(metres, words: true),
      if (zh) const PhrasePart(VoicePhraseId.thereIs) else const PausePart(','),
      PhrasePart(camera),
      if (road.isNotEmpty) ...[
        if (zh) ...[
          const PausePart('，', road: true),
          const PhrasePart(VoicePhraseId.locatedOn, road: true),
        ] else
          const PhrasePart(VoicePhraseId.on, road: true),
        DynamicPart(road, road: true),
      ],
      PausePart(zh ? '。' : '.'),
    ]);
  }

  static String cameraPhrase(CameraKind kind) => switch (kind) {
    CameraKind.spotSpeed => VoicePhraseId.cameraSpeed,
    CameraKind.averageSpeed => VoicePhraseId.cameraAverage,
    CameraKind.redLight => VoicePhraseId.cameraRedLight,
    CameraKind.dualRedLightSpeed => VoicePhraseId.cameraRedLightSpeed,
    CameraKind.busLane => VoicePhraseId.cameraBusLane,
    CameraKind.other => VoicePhraseId.cameraSafety,
  };

  /// "Ahead, Queen Street. Bus lane. Monday to Friday, 07:00 to 10:00. Stay
  /// in a general traffic lane." with the same wording as the lane card.
  static VoiceUtterance transitLane(TransitLaneNotice notice, String language) {
    final zh = language == 'zh';
    final lane = notice.lane;
    final road = lane.roadName.trim();
    final stop = PausePart(zh ? '。' : '.');
    return VoiceUtterance(language, [
      const PhrasePart(VoicePhraseId.ahead),
      if (!zh) const PausePart(','),
      if (road.isNotEmpty) ...[
        DynamicPart(road, road: true),
        PausePart(zh ? '，' : '.', road: true),
      ],
      PhrasePart(transitLanePhrase(lane)),
      stop,
      ...scheduleParts(lane.schedule, language),
      stop,
      PhrasePart(transitInstructionPhrase(notice)),
      stop,
    ]);
  }

  static String transitLanePhrase(TransitLane lane) {
    if (lane.kind.startsWith('T2')) return VoicePhraseId.laneT2;
    if (lane.kind.startsWith('T3')) return VoicePhraseId.laneT3;
    if (lane.kind == 'Truck') return VoicePhraseId.laneTruck;
    return VoicePhraseId.laneBus;
  }

  /// The phrase for [TransitLaneNotice.instruction].
  static String transitInstructionPhrase(TransitLaneNotice notice) {
    final lane = notice.lane;
    if (!lane.directionKnown || !lane.schedule.known) {
      return VoicePhraseId.laneCheckSigns;
    }
    if (lane.wholeRoad) return VoicePhraseId.laneNoCars;
    if (lane.kind.startsWith('T2') || lane.kind.startsWith('T3')) {
      return VoicePhraseId.laneCheckOccupancy;
    }
    return notice.turningLeft
        ? VoicePhraseId.laneTurningLeft
        : VoicePhraseId.laneStayGeneral;
  }

  /// [TransitSchedule.label] as spoken: days and "to" are phrases, clock
  /// times are dynamic numbers.
  static List<UtterancePart> scheduleParts(
    TransitSchedule schedule,
    String language,
  ) {
    final zh = language == 'zh';
    if (!schedule.known) {
      return const [PhrasePart(VoicePhraseId.hoursUnconfirmed)];
    }
    final days = schedule.days;
    final everyDay = days.length == 7;
    final List<UtterancePart> day = everyDay
        ? const [PhrasePart(VoicePhraseId.everyDay)]
        : days.join(',') == '1,2,3,4,5'
        ? const [PhrasePart(VoicePhraseId.weekdays)]
        : [
            for (var i = 0; i < days.length; i++) ...[
              if (i > 0) PausePart(zh ? '、' : ','),
              PhrasePart(VoicePhraseId.day(days[i])),
            ],
          ];
    final windows = schedule.windows;
    if (windows.length == 1 &&
        windows.first[0] == 0 &&
        windows.first[1] == 1440) {
      if (everyDay) return const [PhrasePart(VoicePhraseId.allDayEveryDay)];
      return [
        ...day,
        if (!zh) const PausePart(','),
        const PhrasePart(VoicePhraseId.allDay),
      ];
    }
    List<UtterancePart> time(int minutes) {
      final hour = minutes ~/ 60, minute = minutes % 60;
      if (!zh) {
        return [
          DynamicPart(
            '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
          ),
        ];
      }
      return [
        DynamicPart('$hour'),
        const PhrasePart(VoicePhraseId.timeHour),
        if (minute != 0) ...[
          DynamicPart('$minute'),
          const PhrasePart(VoicePhraseId.timeMinute),
        ],
      ];
    }

    return [
      ...day,
      if (!zh) const PausePart(','),
      for (var i = 0; i < windows.length; i++) ...[
        if (i > 0) PausePart(zh ? '、' : ','),
        ...time(windows[i][0]),
        const PhrasePart(VoicePhraseId.timeTo),
        ...time(windows[i][1]),
      ],
    ];
  }

  /// "You have arrived. Well done!" / "已到达目的地，这段旅程辛苦啦！"
  static VoiceUtterance arrival(String language) => VoiceUtterance(language, [
    const PhrasePart(VoicePhraseId.arrived),
    PausePart(language == 'zh' ? '，' : '.'),
    const PhrasePart(VoicePhraseId.wellDone),
  ]);

  /// "Transit trip started. Follow the itinerary."
  static VoiceUtterance transitTripStarted(String language) => VoiceUtterance(
    language,
    const [PhrasePart(VoicePhraseId.transitTripStarted)],
  );
}
