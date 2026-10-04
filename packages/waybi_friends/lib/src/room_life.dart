import 'dart:math' as math;

enum FriendKind { waybi, clover, sett }

enum FriendActivity {
  idle,
  walking,
  running,
  sitting,
  sleeping,
  watching,
  packing,
  away,
}

enum RoomMoment {
  waking,
  cloverWalking,
  atWindow,
  settFollowing,
  settling,
  napping,
  exploring,
  departing,
  returning,
  waybiAway,
}

class RoomPosition {
  const RoomPosition(this.x, this.y);
  final double x;
  final double y;

  RoomPosition towards(RoomPosition other, double progress) {
    final t = progress.clamp(0.0, 1.0);
    return RoomPosition(x + (other.x - x) * t, y + (other.y - y) * t);
  }
}

class FriendPose {
  const FriendPose({
    required this.kind,
    required this.position,
    this.activity = FriendActivity.idle,
    this.facingRight = true,
    this.opacity = 1,
    this.backpack = false,
  });
  final FriendKind kind;
  final RoomPosition position;
  final FriendActivity activity;
  final bool facingRight;
  final double opacity;
  final bool backpack;
  bool get moving =>
      activity == FriendActivity.walking || activity == FriendActivity.running;
}

class RoomFrame {
  const RoomFrame(this.friends, this.moment, this.seconds);
  final List<FriendPose> friends;
  final RoomMoment moment;
  final double seconds;
  FriendPose friend(FriendKind kind) =>
      friends.firstWhere((p) => p.kind == kind);
}

/// A saved clock anchor, rather than a timer or an animation frame.
/// Sampling the same time gives the same room, including after an app restart.
class RoomLife {
  const RoomLife({required this.startedAt, this.departedAt, this.arrivedAt});
  final DateTime startedAt;
  final DateTime? departedAt;
  final DateTime? arrivedAt;

  static const sofa = RoomPosition(.24, .77);
  static const window = RoomPosition(.54, .63);
  static const rug = RoomPosition(.45, .90);
  static const besideWindow = RoomPosition(.31, .82);
  static const waybiHome = RoomPosition(.73, .86);
  static const door = RoomPosition(.94, .72);

  RoomLife departing(DateTime now) =>
      RoomLife(startedAt: startedAt, departedAt: now);
  RoomLife arriving(DateTime now) =>
      RoomLife(startedAt: startedAt, arrivedAt: now);

  Map<String, dynamic> toJson() => {
    'startedAt': startedAt.toIso8601String(),
    'departedAt': departedAt?.toIso8601String(),
    'arrivedAt': arrivedAt?.toIso8601String(),
  };

  factory RoomLife.fromJson(Map<String, dynamic> json) => RoomLife(
    startedAt: DateTime.parse(json['startedAt'] as String),
    departedAt: DateTime.tryParse(json['departedAt'] as String? ?? ''),
    arrivedAt: DateTime.tryParse(json['arrivedAt'] as String? ?? ''),
  );

  RoomFrame sample(DateTime now, {required bool waybiAway}) {
    final seconds = math.max(
      0.0,
      now.difference(startedAt).inMicroseconds / 1e6,
    );
    final t = seconds % 90;
    var moment = RoomMoment.waking;
    var cloverPosition = sofa;
    var cloverActivity = FriendActivity.sitting;
    var cloverFacing = true;
    var settPosition = rug;
    var settActivity = FriendActivity.idle;
    var settFacing = true;

    if (t >= 4 && t < 9) {
      cloverPosition = sofa.towards(window, (t - 4) / 5);
      cloverActivity = FriendActivity.walking;
      moment = RoomMoment.cloverWalking;
    } else if (t >= 9 && t < 29) {
      cloverPosition = window;
      cloverActivity = FriendActivity.watching;
      moment = RoomMoment.atWindow;
    } else if (t >= 29 && t < 35) {
      cloverPosition = window.towards(sofa, (t - 29) / 6);
      cloverActivity = FriendActivity.walking;
      cloverFacing = false;
      moment = RoomMoment.settling;
    } else if (t >= 35 && t < 58) {
      cloverActivity = FriendActivity.sleeping;
      moment = RoomMoment.napping;
    } else if (t >= 58 && t < 64) {
      cloverPosition = sofa.towards(window, (t - 58) / 6);
      cloverActivity = FriendActivity.walking;
      moment = RoomMoment.cloverWalking;
    } else if (t >= 64) {
      cloverPosition = window;
      cloverActivity = FriendActivity.watching;
      moment = RoomMoment.atWindow;
    }

    if (t >= 7 && t < 11) {
      settPosition = rug.towards(besideWindow, (t - 7) / 4);
      settActivity = FriendActivity.running;
      settFacing = false;
      moment = RoomMoment.settFollowing;
    } else if (t >= 11 && t < 18) {
      settPosition = besideWindow;
      settActivity = FriendActivity.watching;
    } else if (t >= 18 && t < 24) {
      settPosition = besideWindow.towards(
        const RoomPosition(.65, .92),
        (t - 18) / 6,
      );
      settActivity = FriendActivity.running;
      moment = RoomMoment.exploring;
    } else if (t >= 24 && t < 29) {
      settPosition = const RoomPosition(.65, .92).towards(rug, (t - 24) / 5);
      settActivity = FriendActivity.walking;
      settFacing = false;
    } else if (t >= 35 && t < 58) {
      settActivity = FriendActivity.sitting;
    } else if (t >= 61 && t < 65) {
      settPosition = rug.towards(besideWindow, (t - 61) / 4);
      settActivity = FriendActivity.running;
      settFacing = false;
      moment = RoomMoment.settFollowing;
    } else if (t >= 65 && t < 82) {
      settPosition = besideWindow;
      settActivity = FriendActivity.watching;
    } else if (t >= 82) {
      settPosition = besideWindow.towards(rug, (t - 82) / 8);
      settActivity = FriendActivity.walking;
      settFacing = false;
    }

    var waybi = const FriendPose(kind: FriendKind.waybi, position: waybiHome);
    final departure = departedAt == null
        ? double.infinity
        : now.difference(departedAt!).inMicroseconds / 1e6;
    final arrival = arrivedAt == null
        ? double.infinity
        : now.difference(arrivedAt!).inMicroseconds / 1e6;
    if (waybiAway && departure >= 0 && departure < 4) {
      final progress = ((departure - .8) / 2.7).clamp(0.0, 1.0);
      waybi = FriendPose(
        kind: FriendKind.waybi,
        position: waybiHome.towards(door, progress),
        backpack: true,
        activity: departure < .8
            ? FriendActivity.packing
            : FriendActivity.walking,
        opacity: departure < 3.5 ? 1 : ((4 - departure) / .5).clamp(0.0, 1.0),
      );
      moment = RoomMoment.departing;
    } else if (waybiAway) {
      waybi = const FriendPose(
        kind: FriendKind.waybi,
        position: door,
        activity: FriendActivity.away,
        opacity: 0,
      );
      if (moment == RoomMoment.waking) moment = RoomMoment.waybiAway;
    } else if (arrival >= 0 && arrival < 4) {
      waybi = FriendPose(
        kind: FriendKind.waybi,
        position: door.towards(waybiHome, arrival / 4),
        facingRight: false,
        activity: FriendActivity.walking,
        backpack: true,
      );
      moment = RoomMoment.returning;
    }

    return RoomFrame(
      [
        FriendPose(
          kind: FriendKind.clover,
          position: cloverPosition,
          activity: cloverActivity,
          facingRight: cloverFacing,
        ),
        FriendPose(
          kind: FriendKind.sett,
          position: settPosition,
          activity: settActivity,
          facingRight: settFacing,
        ),
        waybi,
      ],
      moment,
      seconds,
    );
  }
}
