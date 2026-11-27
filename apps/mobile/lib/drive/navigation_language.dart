import 'package:google_navigation_flutter/google_navigation_flutter.dart';

import '../domain/route_option.dart';
import 'voice_phrases.dart';
import 'voice_utterance.dart';

String routeStepInstruction(RouteStepInfo? step, String language) {
  final chinese = language == 'zh';
  final supplied = step?.instruction.trim() ?? '';
  if (supplied.isNotEmpty &&
      (!chinese || RegExp(r'[\u3400-\u9fff]').hasMatch(supplied))) {
    return supplied;
  }
  // OSRM exposes structured maneuver type/modifier/name rather than a ready
  // human sentence. Always synthesize a useful prompt when instruction is
  // empty; otherwise English Practice navigation ends up with a blank card
  // and silent TTS.
  return renderUtteranceParts(routeStepParts(step, language), language);
}

/// The fixed phrase for a structured OSRM-style maneuver.
String routeStepActionPhrase(RouteStepInfo step) {
  final type = step.maneuverType.toLowerCase();
  final modifier = step.maneuverModifier.toLowerCase();
  if (type == 'arrive') return VoicePhraseId.arriveAtDestination;
  if (type == 'depart') return VoicePhraseId.depart;
  if (type.startsWith('exit ') &&
      (type.contains('roundabout') || type == 'exit rotary')) {
    return VoicePhraseId.exitRoundabout;
  }
  if (type.contains('roundabout') || type == 'rotary') {
    return VoicePhraseId.roundabout;
  }
  if (modifier == 'uturn') return VoicePhraseId.uturn;
  if (type == 'merge') return VoicePhraseId.merge;
  if (type == 'off ramp' || type == 'offramp') {
    return modifier.contains('left')
        ? VoicePhraseId.exitLeft
        : VoicePhraseId.exitRight;
  }
  if (type == 'on ramp' || type == 'onramp') return VoicePhraseId.ramp;
  if (type == 'fork') {
    return modifier.contains('left')
        ? VoicePhraseId.keepLeft
        : VoicePhraseId.keepRight;
  }
  if (modifier.contains('slight left')) return VoicePhraseId.bearLeft;
  if (modifier.contains('slight right')) return VoicePhraseId.bearRight;
  if (modifier.contains('sharp left')) return VoicePhraseId.sharpLeft;
  if (modifier.contains('sharp right')) return VoicePhraseId.sharpRight;
  if (modifier.contains('left')) return VoicePhraseId.turnLeft;
  if (modifier.contains('right')) return VoicePhraseId.turnRight;
  return VoicePhraseId.continueStraight;
}

/// A maneuver as parts: the action, then the road it leads to
/// ("Turn left onto Queen Street", "左转，驶向 Queen Street").
List<UtterancePart> routeStepParts(RouteStepInfo? step, String language) {
  if (step == null) return const [PhrasePart(VoicePhraseId.continueRoute)];
  final action = routeStepActionPhrase(step);
  final road = step.roadName.trim();
  return [
    PhrasePart(action),
    if (road.isNotEmpty && action != VoicePhraseId.arriveAtDestination)
      ...roadNameParts(
        road,
        language,
        connector: action == VoicePhraseId.depart
            ? VoicePhraseId.on
            : VoicePhraseId.onto,
      ),
  ];
}

/// "onto Queen Street" / "，驶向 Queen Street", flagged as road-name parts.
/// Chinese always uses "驶向"; English uses [connector].
List<UtterancePart> roadNameParts(
  String road,
  String language, {
  String connector = VoicePhraseId.onto,
}) => language == 'zh'
    ? [
        const PausePart('，', road: true),
        const PhrasePart(VoicePhraseId.toward, road: true),
        DynamicPart(road, road: true),
      ]
    : [PhrasePart(connector, road: true), DynamicPart(road, road: true)];

/// Localize structured maneuvers immediately, even when native map labels
/// still use the language selected when the SDK process was initialized.
String navigationInstruction(StepInfo? step, String language) {
  final chinese = language == 'zh';
  if (step == null) return chinese ? '沿路线继续行驶' : 'Continue on route';
  final supplied = step.fullInstructions?.trim() ?? '';
  if (!chinese && supplied.isNotEmpty) return supplied;
  if (chinese && RegExp(r'[\u3400-\u9fff]').hasMatch(supplied)) return supplied;
  final name = step.maneuver.name.toLowerCase();
  final road = step.fullRoadName?.trim() ?? step.simpleRoadName?.trim() ?? '';
  String action;
  if (name.startsWith('destination')) {
    action = chinese ? '到达目的地' : 'Arrive at destination';
  } else if (name.contains('roundabout')) {
    final exit = step.roundaboutTurnNumber;
    action = exit != null && exit > 0
        ? (chinese
              ? '进入环岛，从第 $exit 个出口驶出'
              : 'At the roundabout, take exit $exit')
        : (chinese ? '驶入环岛' : 'Enter the roundabout');
  } else if (name.contains('uturn')) {
    action = chinese ? '掉头' : 'Make a U-turn';
  } else if (name.startsWith('offramp')) {
    final side = name.contains('left')
        ? (chinese ? '左侧' : 'left')
        : name.contains('right')
        ? (chinese ? '右侧' : 'right')
        : '';
    action = chinese
        ? '从$side出口驶出'
        : 'Take the $side exit'.replaceAll('  ', ' ');
    if (step.exitNumber?.isNotEmpty ?? false) action += ' ${step.exitNumber}';
  } else if (name.contains('keep') || name.startsWith('fork')) {
    action = name.contains('left')
        ? (chinese ? '靠左行驶' : 'Keep left')
        : (chinese ? '靠右行驶' : 'Keep right');
  } else if (name.startsWith('merge')) {
    action = chinese ? '汇入前方道路' : 'Merge ahead';
  } else if (name.startsWith('onramp')) {
    action = chinese ? '驶入匝道' : 'Take the ramp';
  } else if (name.contains('left')) {
    action = chinese
        ? (name.contains('sharp')
              ? '向左急转'
              : name.contains('slight')
              ? '向左前方行驶'
              : '左转')
        : 'Turn left';
  } else if (name.contains('right')) {
    action = chinese
        ? (name.contains('sharp')
              ? '向右急转'
              : name.contains('slight')
              ? '向右前方行驶'
              : '右转')
        : 'Turn right';
  } else if (name.contains('ferry')) {
    action = chinese ? '搭乘渡轮' : 'Take the ferry';
  } else {
    action = chinese ? '继续直行' : 'Continue straight';
  }
  if (road.isEmpty || name.startsWith('destination')) return action;
  return chinese ? '$action，驶向 $road' : '$action toward $road';
}

String navigationMetres(num metres, String language) {
  final safe = metres.isFinite ? metres.clamp(0, double.infinity) : 0;
  if (safe >= 1000) {
    return '${(safe / 1000).toStringAsFixed(1)} ${language == 'zh' ? '公里' : 'km'}';
  }
  return '${safe.round()} ${language == 'zh' ? '米' : 'm'}';
}
