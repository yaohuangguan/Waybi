import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/map_layer_settings.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/domain/transit_lane.dart';
import 'package:waybi_mobile/drive/custom_voice.dart';
import 'package:waybi_mobile/drive/navigation_language.dart';
import 'package:waybi_mobile/drive/voice_engine.dart';
import 'package:waybi_mobile/drive/voice_prompts.dart';

import 'custom_voice_test.dart' show FakeClipPlayer, FakeClips, RecordingTts;

RouteStepInfo step(
  String type,
  String modifier, {
  String road = '',
  String instruction = '',
}) => RouteStepInfo(
  instruction: instruction,
  distanceMeters: 100,
  location: const GeoPoint(-36.85, 174.76),
  maneuverType: type,
  maneuverModifier: modifier,
  roadName: road,
);

TransitLaneNotice lane({
  String road = 'Queen Street',
  String kind = 'Bus',
  TransitSchedule schedule = const TransitSchedule(
    days: [1, 2, 3, 4, 5],
    windows: [
      [420, 600],
      [960, 1110],
    ],
    known: true,
  ),
  bool directionKnown = true,
  bool wholeRoad = false,
  bool turningLeft = false,
}) => TransitLaneNotice(
  match: TransitLaneMatch(
    lane: TransitLane(
      id: 'lane',
      roadName: road,
      kind: kind,
      schedule: schedule,
      points: const [],
      directionKnown: directionKnown,
      wholeRoad: wholeRoad,
    ),
    startMeters: 0,
    endMeters: 100,
  ),
  distanceMeters: 50,
  turningLeft: turningLeft,
);

List<String> describe(List<VoiceSegment> segments) => [
  for (final segment in segments)
    switch (segment) {
      ClipSegment(:final phraseId) => 'clip:$phraseId',
      TtsSegment(:final text) => 'tts:$text',
    },
];

Set<String> everything(String language) => {
  for (final phrase in voicePhrasesFor(language)) phrase.id,
};

const schedules = [
  TransitSchedule(
    days: [1, 2, 3, 4, 5],
    windows: [
      [420, 570],
    ],
    known: true,
  ),
  TransitSchedule(
    days: [1, 2, 3, 4, 5, 6, 7],
    windows: [
      [0, 1440],
    ],
    known: true,
  ),
  TransitSchedule(
    days: [6, 7],
    windows: [
      [0, 1440],
    ],
    known: true,
  ),
  TransitSchedule(
    days: [1, 3],
    windows: [
      [450, 600],
      [960, 1110],
    ],
    known: true,
  ),
  TransitSchedule(
    days: [1, 2, 3, 4, 5, 6, 7],
    windows: [
      [420, 600],
    ],
    known: true,
  ),
  TransitSchedule(days: [], windows: [], known: false),
];

/// Every kind of prompt the app can speak, in [language].
List<(String, VoiceUtterance)> everyPrompt(
  String language, {
  bool roads = true,
}) {
  final road = roads ? 'Wakefield Place' : '';
  final steps = [
    step('turn', 'left', road: road),
    step('turn', 'right', road: road),
    step('turn', 'slight left', road: road),
    step('turn', 'slight right', road: road),
    step('turn', 'sharp left', road: road),
    step('turn', 'sharp right', road: road),
    step('turn', 'uturn', road: road),
    step('continue', 'straight', road: road),
    step('new name', '', road: road),
    step('depart', 'right', road: road),
    step('arrive', 'left', road: road),
    step('merge', 'slight left', road: road),
    step('on ramp', 'right', road: road),
    step('off ramp', 'left', road: road),
    step('off ramp', 'slight right', road: road),
    step('fork', 'left', road: road),
    step('fork', 'right', road: road),
    step('roundabout', 'right', road: road),
    step('rotary', '', road: road),
    step('exit roundabout', 'right', road: road),
    step(
      'turn',
      'left',
      road: road,
      instruction: 'Turn left onto Wakefield Place toward Albany.',
    ),
  ];
  return [
    ('opening (no step)', VoicePrompts.routeStep(null, language)),
    for (final s in steps) ...[
      (
        '${s.maneuverType} ${s.maneuverModifier}',
        VoicePrompts.turn(s, language),
      ),
      for (final metres in [48.0, 287.0, 650.0, 800.0, 1234.0, 1700.0])
        (
          '${s.maneuverType} at $metres',
          VoicePrompts.turn(s, language, metres: metres),
        ),
    ],
    for (final kind in CameraKind.values)
      for (final metres in [300, 476, 800, 150])
        (
          'camera $kind $metres',
          VoicePrompts.camera(
            metres: metres,
            cameraType: kind.label,
            roadName: road,
            language: language,
          ),
        ),
    for (final schedule in schedules)
      for (final kind in ['Bus', 'T2', 'T3', 'Truck'])
        for (final turningLeft in [false, true])
          (
            'lane $kind ${schedule.days} ${schedule.windows}',
            VoicePrompts.transitLane(
              lane(
                road: road,
                kind: kind,
                schedule: schedule,
                turningLeft: turningLeft,
              ),
              language,
            ),
          ),
    (
      'lane direction unknown',
      VoicePrompts.transitLane(
        lane(road: road, directionKnown: false),
        language,
      ),
    ),
    (
      'lane whole road',
      VoicePrompts.transitLane(lane(road: road, wholeRoad: true), language),
    ),
    ('arrival', VoicePrompts.arrival(language)),
    ('transit trip', VoicePrompts.transitTripStarted(language)),
  ];
}

Set<String> dynamicTexts(VoiceUtterance prompt) => {
  for (final part in prompt.parts)
    if (part is DynamicPart)
      part.text
    else if (part is DistancePart)
      part.number,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('sentences built from parts', () {
    test('maneuvers read the same as before for the standard voice', () {
      expect(
        VoicePrompts.routeStep(
          step('turn', 'right', road: 'Queen Street'),
          'en',
        ).text,
        'Turn right onto Queen Street',
      );
      expect(
        VoicePrompts.routeStep(
          step('turn', 'left', road: 'Wakefield Place'),
          'zh',
        ).text,
        '左转，驶向 Wakefield Place',
      );
      expect(VoicePrompts.routeStep(step('fork', 'left'), 'zh').text, '靠左行驶');
      expect(VoicePrompts.routeStep(null, 'en').text, 'Continue on route');
      expect(
        VoicePrompts.routeStep(
          step('depart', 'right', road: 'Queen Street'),
          'en',
        ).text,
        'Head out on Queen Street',
      );
      expect(
        VoicePrompts.routeStep(step('exit roundabout', 'right'), 'en').text,
        'Exit the roundabout',
      );
      expect(
        VoicePrompts.routeStep(
          step('arrive', 'left', road: 'Queen Street'),
          'zh',
        ).text,
        '到达目的地',
      );
      expect(
        VoicePrompts.turn(
          step('turn', 'left', road: '皇后街'),
          'zh',
          metres: 300,
        ).text,
        '300 米后，左转，驶向皇后街',
      );
      expect(
        VoicePrompts.turn(
          step('turn', 'left', road: 'Queen St'),
          'en',
          metres: 1234,
        ).text,
        'In 1.2 km, Turn left onto Queen St',
      );
    });

    test('a routing engine sentence stays the standard-voice text', () {
      final supplied = step(
        'off ramp',
        'right',
        instruction: 'Take exit 414 towards Constellation Drive.',
      );
      final prompt = VoicePrompts.turn(supplied, 'en', metres: 500);
      expect(
        prompt.text,
        'In 500 m, Take exit 414 towards Constellation Drive.',
      );
      expect(prompt.parts, [
        const DistancePart(500),
        const PausePart(','),
        const PhrasePart(VoicePhraseId.exitRight),
      ]);
      expect(describe(planUtterance(prompt, {'in_500', 'exit_right'})), [
        'clip:in_500',
        'clip:exit_right',
      ]);
      expect(describe(planUtterance(prompt, {'unrelated'})), [
        'tts:In 500 m, Take exit 414 towards Constellation Drive.',
      ], reason: 'Without a usable clip the engine sentence is read unchanged');
    });

    test(
      'a sentence without maneuver fields falls back to phrase matching',
      () {
        final prompt = VoicePrompts.turn(
          step('', '', instruction: 'Turn left onto Queen Street'),
          'en',
          metres: 300,
        );
        expect(prompt.structured, isFalse);
        expect(prompt.text, 'In 300 m, Turn left onto Queen Street');
        expect(
          VoicePrompts.routeStep(
            step('', '', instruction: 'Go'),
            'en',
          ).structured,
          isFalse,
        );
      },
    );

    test('camera wording composes cleanly in both languages', () {
      String camera(String language, String road, {num metres = 300}) =>
          VoicePrompts.camera(
            metres: metres,
            cameraType: 'Spot speed',
            roadName: road,
            language: language,
          ).text;
      expect(
        camera('en', 'Queen Street'),
        'In 300 metres, speed camera on Queen Street.',
      );
      expect(camera('en', ' '), 'In 300 metres, speed camera.');
      expect(camera('zh', 'Queen Street'), '300 米后有定点测速摄像头，位于 Queen Street。');
      expect(camera('zh', '皇后街'), '300 米后有定点测速摄像头，位于皇后街。');
      expect(camera('zh', ''), '300 米后有定点测速摄像头。');
      expect(
        camera('en', '', metres: 1500),
        'In 1.5 kilometres, speed camera.',
      );
    });

    test('transit lane reminders keep the lane card wording', () {
      final notice = lane();
      expect(
        notice.speech('en'),
        'Ahead, Queen Street. Bus lane. Monday to Friday, 07:00 to 10:00, 16:00 to 18:30. Stay in a general traffic lane.',
      );
      expect(
        notice.speech('zh'),
        '前方 Queen Street，公交车道。周一至周五 7 点至 10 点、16 点至 18 点 30 分。请保持普通车道。',
      );
      expect(
        lane(road: '', schedule: schedules[1]).speech('en'),
        'Ahead, bus lane. Active 24 hours, every day. Stay in a general traffic lane.',
      );
      expect(
        lane(schedule: schedules[2], kind: 'T2').speech('en'),
        'Ahead, Queen Street. T2 transit lane. Saturday, Sunday, 24 hours. Check occupancy requirements or stay in a general lane.',
      );
      expect(lane(schedule: schedules[2]).speech('zh'), contains('周六、周日全天生效'));
      expect(
        lane(schedule: schedules[5]).speech('en'),
        contains(
          'Hours unconfirmed · check signs. Check lane signs and operating hours.',
        ),
      );
      for (final language in ['en', 'zh']) {
        for (final notice in [
          lane(),
          lane(turningLeft: true),
          lane(kind: 'T3'),
          lane(kind: 'Truck'),
          lane(wholeRoad: true),
          lane(directionKnown: false),
        ]) {
          expect(
            customVoicePhrase(VoicePrompts.transitInstructionPhrase(notice))!
                .prompt(language),
            notice.instruction(language),
          );
          expect(
            customVoicePhrase(VoicePrompts.transitLanePhrase(notice.lane))!
                .prompt(language),
            notice.lane.label(language),
          );
        }
      }
    });

    test('camera phrases match the camera labels on screen', () {
      for (final kind in CameraKind.values) {
        for (final language in ['en', 'zh']) {
          expect(
            customVoicePhrase(VoicePrompts.cameraPhrase(kind))!
                .prompt(language),
            kind.cameraLabel(language),
          );
        }
      }
    });

    test('arrival and trip messages match what the app says today', () {
      expect(VoicePrompts.arrival('en').text, 'You have arrived. Well done!');
      expect(VoicePrompts.arrival('zh').text, '已到达目的地，这段旅程辛苦啦！');
      expect(
        VoicePrompts.transitTripStarted('en').text,
        'Transit trip started. Follow the itinerary.',
      );
      expect(VoicePrompts.transitTripStarted('zh').speechLanguage, 'zh-CN');
    });
  });

  group('playing parts', () {
    test(
      'every fixed word is a clip; only the road name is standard voice',
      () {
        final prompt = VoicePrompts.routeStep(
          step('turn', 'left', road: 'Wakefield Place'),
          'zh',
        );
        expect(describe(planUtterance(prompt, {'turn_left', 'conn_toward'})), [
          'clip:turn_left',
          'clip:conn_toward',
          'tts:Wakefield Place',
        ]);
        expect(describe(planUtterance(prompt, {'turn_left'})), [
          'clip:turn_left',
          'tts:驶向 Wakefield Place',
        ], reason: 'An unrecorded connector joins the standard-voice run');
        expect(
          describe(planUtterance(prompt, {'turn_left'}, omitRoadNames: true)),
          ['clip:turn_left'],
        );
      },
    );

    test('distances snap when close, otherwise the number is spelled out', () {
      VoiceUtterance at(num metres, String language) =>
          VoicePrompts.turn(step('turn', 'right'), language, metres: metres);
      expect(describe(planUtterance(at(287, 'en'), {'in_300', 'turn_right'})), [
        'clip:in_300',
        'clip:turn_right',
      ]);
      expect(
        describe(
          planUtterance(at(650, 'en'), {
            'dist_in',
            'dist_metres',
            'turn_right',
          }),
        ),
        ['clip:dist_in', 'tts:650', 'clip:dist_metres', 'clip:turn_right'],
      );
      expect(
        describe(
          planUtterance(at(1700, 'zh'), {'dist_kilometres', 'turn_right'}),
        ),
        ['tts:1.7', 'clip:dist_kilometres', 'clip:turn_right'],
      );
      expect(describe(planUtterance(at(650, 'en'), {'turn_right'})), [
        'tts:In 650 m,',
        'clip:turn_right',
      ], reason: 'With no distance clips the distance reads as one phrase');
    });

    test('road names can be left out with their connectors', () {
      final camera = VoicePrompts.camera(
        metres: 300,
        cameraType: 'average speed',
        roadName: 'Queen Street',
        language: 'zh',
      );
      expect(camera.textWithoutRoadNames, '300 米后有区间测速摄像头。');
      expect(describe(planUtterance(camera, {'in_300'}, omitRoadNames: true)), [
        'clip:in_300',
        'tts:有区间测速摄像头。',
      ]);
      expect(
        describe(planUtterance(camera, {'nothing'}, omitRoadNames: true)),
        ['tts:300 米后有区间测速摄像头。'],
      );
      final transit = VoicePrompts.transitLane(lane(), 'en');
      expect(
        transit.textWithoutRoadNames,
        startsWith('Ahead, bus lane. Monday to Friday'),
      );
      expect(VoiceUtterance.freeform('Hi', 'en').textWithoutRoadNames, 'Hi');
      expect(
        withoutRoadNames(const [
          PausePart(','),
          PhrasePart('ahead'),
          PausePart(','),
          PausePart('.'),
          DynamicPart('x', road: true),
          PausePart(','),
        ]),
        const [PhrasePart('ahead'), PausePart('.')],
      );
      expect(
        planUtterance(
          VoiceUtterance('en', const [DynamicPart('Queen St', road: true)]),
          {'turn_left'},
          omitRoadNames: true,
        ),
        isEmpty,
      );
    });

    test(
      'with every phrase recorded, only dynamic text uses the standard voice',
      () {
        for (final language in ['en', 'zh']) {
          final recorded = everything(language);
          for (final roads in [true, false]) {
            for (final (name, prompt) in everyPrompt(language, roads: roads)) {
              final where = '$language $name (roads: $roads)';
              expect(prompt.structured, isTrue, reason: where);
              expect(prompt.text, isNotEmpty, reason: where);
              for (final part in prompt.parts.whereType<PhrasePart>()) {
                expect(
                  customVoicePhrase(part.phraseId)?.availableIn(language),
                  isTrue,
                  reason: '$where uses ${part.phraseId}',
                );
              }
              final dynamic = dynamicTexts(prompt);
              for (final omit in [false, true]) {
                final segments = planUtterance(
                  prompt,
                  recorded,
                  omitRoadNames: omit,
                );
                expect(segments, isNotEmpty, reason: where);
                for (final segment in segments.whereType<TtsSegment>()) {
                  var rest = segment.text;
                  for (final text in dynamic) {
                    rest = rest.replaceAll(text, '');
                  }
                  expect(
                    rest.replaceAll(RegExp(r'[\s,.;:!?，。；：！？、·]'), ''),
                    isEmpty,
                    reason: '$where: "${segment.text}" is fixed wording',
                  );
                  if (omit) {
                    expect(
                      segment.text,
                      isNot(contains('Wakefield')),
                      reason: where,
                    );
                  }
                }
              }
            }
          }
        }
      },
    );

    test('each language pack offers unique wording', () {
      final ids = customVoicePhrases.map((phrase) => phrase.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final language in ['en', 'zh']) {
        final prompts = voicePhrasesFor(language)
            .map((p) => p.prompt(language));
        expect(prompts.toSet(), hasLength(prompts.length), reason: language);
        for (final phrase in voicePhrasesFor(language)) {
          expect(RegExp(r'^[a-z0-9_]{1,48}$').hasMatch(phrase.id), isTrue);
        }
      }
      expect(
        voicePhrasesFor('en', VoicePhraseGroup.connector).map((p) => p.id),
        ['conn_onto', 'conn_toward', 'conn_on'],
      );
      expect(customVoicePhrase('missing'), isNull);
    });

    test('rendering details', () {
      expect(utterancePartText(const PhrasePart('missing'), 'en'), '');
      expect(
        renderUtteranceParts(const [
          PausePart('.'),
          PhrasePart('turn_left'),
          PhrasePart('missing'),
          PhrasePart('lane_t2'),
          PhrasePart('uturn'),
        ], 'en'),
        'Turn left T2 transit lane make a U-turn',
      );
      expect(
        renderUtteranceParts(const [DynamicPart('queen st')], 'en'),
        'queen st',
        reason: 'Names keep their own case',
      );
      expect(const DistancePart(double.nan).text('en'), 'In 0 m');
      expect(const DistancePart(-5, words: true).text('en'), 'In 0 metres');
      expect(const DistancePart(2000).snap({'in_2000'}), 'in_2000');
      expect(const DistancePart(2300).snap({'in_2000'}), isNull);
      expect(VoiceUtterance('zh', const []).isEmpty, isTrue);
    });

    test('parts compare by value', () {
      expect(const PhrasePart('a'), const PhrasePart('a'));
      expect(const PhrasePart('a').hashCode, const PhrasePart('a').hashCode);
      expect(const PhrasePart('a'), isNot(const PhrasePart('a', road: true)));
      expect(const DynamicPart('x').hashCode, const DynamicPart('x').hashCode);
      expect(const DistancePart(5), const DistancePart(5));
      expect(const DistancePart(5).hashCode, const DistancePart(5).hashCode);
      expect(const PausePart(',').hashCode, const PausePart(',').hashCode);
      expect('${const PhrasePart('a')}', 'Phrase(a)');
      expect('${const DynamicPart('x')}', 'Dynamic(x)');
      expect('${const DistancePart(5)}', 'Distance(5)');
      expect('${const PausePart(',')}', 'Pause(,)');
      expect(
        '${VoiceUtterance('en', const [PhrasePart('a')])}',
        'VoiceUtterance(en, [Phrase(a)])',
      );
    });
  });

  group('voice engine with structured prompts', () {
    late RecordingTts tts;
    late FakeClipPlayer player;
    setUp(() {
      tts = RecordingTts();
      player = FakeClipPlayer(tts.events);
    });

    test('plays recorded connectors and reads only the road name', () async {
      final voice = VoiceEngine(
        tts: tts,
        customVoice: FakeClips({'turn_left', 'conn_toward'}),
        clipPlayer: () => player,
      );
      final prompt = VoicePrompts.routeStep(
        step('turn', 'left', road: 'Wakefield Place'),
        'zh',
      );
      expect(await voice.say(prompt), isTrue);
      expect(tts.events, [
        'clip:turn_left.m4a',
        'clip:conn_toward.m4a',
        'tts:Wakefield Place',
      ]);
      await voice.dispose();
    });

    test('road names are skipped when the member asks', () async {
      final voice = VoiceEngine(
        tts: tts,
        customVoice: FakeClips({'turn_left', 'in_300'}, omitRoadNames: true),
        clipPlayer: () => player,
      );
      expect(
        await voice.turnUtterance(
          () => VoicePrompts.turn(
            step('turn', 'left', road: 'Queen Street'),
            'en',
            metres: 296,
          ),
          urgent: true,
        ),
        isTrue,
      );
      expect(tts.events, ['clip:in_300.m4a', 'clip:turn_left.m4a']);
      await voice.dispose();
    });

    test('without clips the standard voice reads the full sentence', () async {
      final voice = VoiceEngine(tts: tts);
      await voice.roadAlertUtterance(
        () => VoicePrompts.transitLane(lane(), 'en'),
      );
      expect(tts.spoken.single, lane().speech('en'));
      expect(
        await voice.say(VoiceUtterance.freeform(' ', 'en')),
        isFalse,
        reason: 'Nothing to say',
      );
      await voice.dispose();
    });

    test(
      'a camera alert plays the distance, connector and camera clips',
      () async {
        final voice = VoiceEngine(
          tts: tts,
          customVoice: FakeClips({
            'in_300',
            'conn_there_is',
            'camera_speed',
            'conn_located',
          }),
          clipPlayer: () => player,
        );
        await voice.setLanguage('zh-CN');
        await voice.cameraAlert(
          distanceMeters: 300,
          cameraType: 'Spot speed',
          roadName: 'Queen Street',
        );
        expect(tts.events, [
          'clip:in_300.m4a',
          'clip:conn_there_is.m4a',
          'clip:camera_speed.m4a',
          'clip:conn_located.m4a',
          'tts:Queen Street。',
        ]);
        await voice.dispose();
      },
    );

    test('free-form arrival from the host still finds both clips', () {
      expect(
        describe(
          planCustomVoice('You have arrived. Well done!', 'en', {
            'arrived',
            'well_done',
          }),
        ),
        ['clip:arrived', 'clip:well_done'],
      );
      expect(
        describe(
          planCustomVoice('Transit trip started. Follow the itinerary.', 'en', {
            'trip_transit_started',
          }),
        ),
        ['clip:trip_transit_started'],
      );
      expect(describe(planCustomVoice('On Queen Street', 'en', {'conn_on'})), [
        'tts:On Queen Street',
      ], reason: 'Glue words never match on their own');
    });
  });

  test('navigation metres stay in step with spoken distances', () {
    for (final metres in [0, 49.6, 300, 999.4, 1000, 1234, 1750]) {
      for (final language in ['en', 'zh']) {
        final spoken = DistancePart(metres).text(language);
        final shown = navigationMetres(metres, language);
        expect(
          spoken,
          language == 'zh' ? '$shown后' : 'In $shown',
          reason: '$metres $language',
        );
      }
    }
  });
}
