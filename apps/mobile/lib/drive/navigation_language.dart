import 'package:google_navigation_flutter/google_navigation_flutter.dart';

import '../domain/route_option.dart';

String routeStepInstruction(RouteStepInfo? step, String language) {
  final chinese = language == 'zh';
  if (step == null) return chinese ? '沿路线继续行驶' : 'Continue on route';
  final supplied = step.instruction.trim();
  if (supplied.isNotEmpty &&
      (!chinese || RegExp(r'[\u3400-\u9fff]').hasMatch(supplied))) {
    return supplied;
  }

  // OSRM exposes structured maneuver type/modifier/name rather than a ready
  // human sentence. Always synthesize a useful prompt when instruction is
  // empty; otherwise English Practice navigation ends up with a blank card
  // and silent TTS.
  final type = step.maneuverType.toLowerCase();
  final modifier = step.maneuverModifier.toLowerCase();
  final road = step.roadName.trim();
  String action;
  if (type == 'arrive') {
    action = chinese ? '到达目的地' : 'Arrive at destination';
  } else if (type.contains('roundabout') || type == 'rotary') {
    action = chinese ? '驶入环岛' : 'Enter the roundabout';
  } else if (modifier == 'uturn') {
    action = chinese ? '掉头' : 'Make a U-turn';
  } else if (type == 'merge') {
    action = chinese ? '汇入前方道路' : 'Merge ahead';
  } else if (type == 'off ramp' || type == 'offramp') {
    final left = modifier.contains('left');
    action = chinese
        ? '从${left ? '左侧' : '右侧'}出口驶出'
        : 'Take the ${left ? 'left' : 'right'} exit';
  } else if (type == 'on ramp' || type == 'onramp') {
    action = chinese ? '驶入匝道' : 'Take the ramp';
  } else if (type == 'fork') {
    final left = modifier.contains('left');
    action = chinese
        ? (left ? '靠左行驶' : '靠右行驶')
        : (left ? 'Keep left' : 'Keep right');
  } else if (modifier.contains('slight left')) {
    action = chinese ? '向左前方行驶' : 'Bear left';
  } else if (modifier.contains('slight right')) {
    action = chinese ? '向右前方行驶' : 'Bear right';
  } else if (modifier.contains('sharp left')) {
    action = chinese ? '向左急转' : 'Turn sharp left';
  } else if (modifier.contains('sharp right')) {
    action = chinese ? '向右急转' : 'Turn sharp right';
  } else if (modifier.contains('left')) {
    action = chinese ? '左转' : 'Turn left';
  } else if (modifier.contains('right')) {
    action = chinese ? '右转' : 'Turn right';
  } else {
    action = chinese ? '继续直行' : 'Continue straight';
  }
  if (road.isEmpty || type == 'arrive') return action;
  return chinese ? '$action，驶向 $road' : '$action onto $road';
}

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
