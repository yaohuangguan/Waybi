import 'package:flutter/material.dart';

/// Shared monochrome vector icon family for native and independent guidance.
IconData navigationManeuverIcon(String type, [String modifier = '']) {
  final name = '$type $modifier'.toLowerCase().replaceAll(RegExp(r'[ _-]'), '');
  final left = name.contains('left');
  if (name.contains('arrive') || name.startsWith('destination')) {
    return Icons.flag_rounded;
  }
  if (name.contains('uturn')) {
    return left || !name.contains('right')
        ? Icons.u_turn_left_rounded
        : Icons.u_turn_right_rounded;
  }
  if (name.contains('roundabout') || name.contains('rotary')) {
    return left
        ? Icons.roundabout_left_rounded
        : Icons.roundabout_right_rounded;
  }
  if (name.contains('offramp') || name.contains('onramp')) {
    return left ? Icons.ramp_left_rounded : Icons.ramp_right_rounded;
  }
  if (name.contains('fork') || name.contains('keep')) {
    return left ? Icons.fork_left_rounded : Icons.fork_right_rounded;
  }
  if (name.contains('merge')) return Icons.merge_rounded;
  if (name.contains('slight')) {
    return left
        ? Icons.turn_slight_left_rounded
        : Icons.turn_slight_right_rounded;
  }
  if (name.contains('sharp')) {
    return left
        ? Icons.turn_sharp_left_rounded
        : Icons.turn_sharp_right_rounded;
  }
  if (name.contains('right')) return Icons.turn_right_rounded;
  if (left) return Icons.turn_left_rounded;
  return Icons.straight_rounded;
}
