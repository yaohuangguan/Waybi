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
  playing,
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
  playing,
}

enum HomeScene { room, garden }

class RoomPosition {
  const RoomPosition(this.x, this.y);
  final double x, y;
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

class FriendInteraction {
  const FriendInteraction(this.at, this.from, this.to);
  final DateTime at;
  final RoomPosition from, to;
  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'from': [from.x, from.y],
    'to': [to.x, to.y],
  };
  factory FriendInteraction.fromJson(Map<String, dynamic> json) =>
      FriendInteraction(
        DateTime.parse(json['at'] as String),
        RoomPosition(
          (json['from'][0] as num).toDouble(),
          (json['from'][1] as num).toDouble(),
        ),
        RoomPosition(
          (json['to'][0] as num).toDouble(),
          (json['to'][1] as num).toDouble(),
        ),
      );
}

/// Wall-clock paths have matching endpoints, including after an app restart.
class RoomLife {
  const RoomLife({
    required this.startedAt,
    this.departedAt,
    this.arrivedAt,
    this.traveller = FriendKind.waybi,
    this.scene = HomeScene.room,
    this.departureFrom,
    this.interactions = const {},
  });
  final DateTime startedAt;
  final DateTime? departedAt, arrivedAt;
  final FriendKind traveller;
  final HomeScene scene;
  final RoomPosition? departureFrom;
  final Map<FriendKind, FriendInteraction> interactions;
  static const sofa = RoomPosition(.24, .77),
      window = RoomPosition(.54, .63),
      rug = RoomPosition(.45, .90),
      besideWindow = RoomPosition(.31, .82),
      waybiHome = RoomPosition(.73, .86),
      door = RoomPosition(.94, .72);
  static RoomPosition home(FriendKind kind) => switch (kind) {
    FriendKind.clover => sofa,
    FriendKind.sett => rug,
    FriendKind.waybi => waybiHome,
  };
  RoomLife departing(DateTime now, [FriendKind kind = FriendKind.waybi]) =>
      RoomLife(
        startedAt: startedAt,
        departedAt: now,
        traveller: kind,
        scene: scene,
        departureFrom: sample(now, waybiAway: false).friend(kind).position,
        interactions: interactions,
      );
  RoomLife arriving(DateTime now) => RoomLife(
    startedAt: startedAt,
    arrivedAt: now,
    traveller: traveller,
    scene: scene,
    interactions: interactions,
  );
  RoomLife changeScene(HomeScene value) => RoomLife(
    startedAt: startedAt,
    departedAt: departedAt,
    arrivedAt: arrivedAt,
    traveller: traveller,
    scene: value,
    departureFrom: departureFrom,
    interactions: interactions,
  );
  RoomLife interact(FriendKind kind, DateTime now, {required bool away}) =>
      RoomLife(
        startedAt: startedAt,
        departedAt: departedAt,
        arrivedAt: arrivedAt,
        traveller: traveller,
        scene: scene,
        departureFrom: departureFrom,
        interactions: {
          ...interactions,
          kind: FriendInteraction(
            now,
            sample(now, waybiAway: away).friend(kind).position,
            kind == FriendKind.clover
                ? window
                : kind == FriendKind.sett
                ? const RoomPosition(.65, .92)
                : const RoomPosition(.59, .82),
          ),
        },
      );
  Map<String, dynamic> toJson() => {
    'startedAt': startedAt.toIso8601String(),
    'departedAt': departedAt?.toIso8601String(),
    'arrivedAt': arrivedAt?.toIso8601String(),
    'traveller': traveller.name,
    'scene': scene.name,
    'departureFrom': departureFrom == null
        ? null
        : [departureFrom!.x, departureFrom!.y],
    'interactions': {
      for (final entry in interactions.entries)
        entry.key.name: entry.value.toJson(),
    },
  };
  factory RoomLife.fromJson(Map<String, dynamic> json) => RoomLife(
    startedAt: DateTime.parse(json['startedAt'] as String),
    departedAt: DateTime.tryParse(json['departedAt'] as String? ?? ''),
    arrivedAt: DateTime.tryParse(json['arrivedAt'] as String? ?? ''),
    traveller: FriendKind.values.firstWhere(
      (k) => k.name == json['traveller'],
      orElse: () => FriendKind.waybi,
    ),
    scene: json['scene'] == 'garden' ? HomeScene.garden : HomeScene.room,
    departureFrom: json['departureFrom'] is List
        ? RoomPosition(
            (json['departureFrom'][0] as num).toDouble(),
            (json['departureFrom'][1] as num).toDouble(),
          )
        : null,
    interactions: {
      for (final kind in FriendKind.values)
        if (json['interactions'] is Map &&
            json['interactions'][kind.name] is Map)
          kind: FriendInteraction.fromJson(
            Map<String, dynamic>.from(json['interactions'][kind.name] as Map),
          ),
    },
  );

  FriendPose _ambient(FriendKind kind, double seconds) {
    final cycle = (seconds / 240).floor();
    final t = seconds % 240;
    final rng = math.Random(
      startedAt.millisecondsSinceEpoch + cycle * 997 + kind.index * 31,
    );
    final origin = home(kind);
    final spots = [
      window,
      besideWindow,
      const RoomPosition(.65, .92),
      const RoomPosition(.71, .72),
    ];
    final first = cycle == 0
        ? (kind == FriendKind.clover
              ? window
              : kind == FriendKind.sett
              ? besideWindow
              : spots[3])
        : spots[rng.nextInt(spots.length)];
    final second = spots[rng.nextInt(spots.length)];
    final start = kind == FriendKind.clover
        ? 4.0
        : kind == FriendKind.sett
        ? 7.0
        : 17.0;
    final walk = kind == FriendKind.sett ? 4.0 : 5.0;
    final pauseEnd = 50.0 + rng.nextInt(65);
    final rest = rng.nextBool()
        ? FriendActivity.sleeping
        : FriendActivity.sitting;
    FriendPose hold(RoomPosition point, FriendActivity activity) =>
        FriendPose(kind: kind, position: point, activity: activity);
    FriendPose move(RoomPosition from, RoomPosition to, double progress) =>
        FriendPose(
          kind: kind,
          position: from.towards(to, progress),
          activity: kind == FriendKind.sett
              ? FriendActivity.running
              : FriendActivity.walking,
          facingRight: to.x >= from.x,
        );
    if (t < start) return hold(origin, FriendActivity.sitting);
    if (t < start + walk) return move(origin, first, (t - start) / walk);
    if (t < pauseEnd) return hold(first, FriendActivity.watching);
    if (t < pauseEnd + 7) return move(first, second, (t - pauseEnd) / 7);
    if (t < 225) return hold(second, rest);
    if (t < 234) return move(second, origin, (t - 225) / 9);
    return hold(origin, FriendActivity.sitting);
  }

  RoomFrame sample(DateTime now, {required bool waybiAway}) {
    final seconds = math.max(
      0.0,
      now.difference(startedAt).inMicroseconds / 1e6,
    );
    final poses = <FriendPose>[];
    var moment = RoomMoment.waking;
    for (final kind in FriendKind.values) {
      var pose = _ambient(kind, seconds);
      final action = interactions[kind];
      if (action != null) {
        final t = now.difference(action.at).inMicroseconds / 1e6;
        if (t >= 0 && t < 4) {
          pose = FriendPose(
            kind: kind,
            position: action.from.towards(action.to, t / 4),
            activity: FriendActivity.walking,
            facingRight: action.to.x >= action.from.x,
          );
        } else if (t >= 4 && t < 30) {
          pose = FriendPose(
            kind: kind,
            position: action.to,
            activity: kind == FriendKind.clover
                ? FriendActivity.watching
                : FriendActivity.playing,
          );
        } else if (t >= 30 && t < 36) {
          final target = _ambient(kind, seconds + 36 - t).position;
          pose = FriendPose(
            kind: kind,
            position: action.to.towards(target, (t - 30) / 6),
            activity: FriendActivity.walking,
            facingRight: target.x >= action.to.x,
          );
        }
      }
      final departure = departedAt == null
          ? double.infinity
          : now.difference(departedAt!).inMicroseconds / 1e6;
      final arrival = arrivedAt == null
          ? double.infinity
          : now.difference(arrivedAt!).inMicroseconds / 1e6;
      if (kind == traveller && waybiAway) {
        final origin = departureFrom ?? home(kind);
        if (departure >= 0 && departure < 4) {
          pose = FriendPose(
            kind: kind,
            position: origin.towards(
              door,
              ((departure - .8) / 2.7).clamp(0.0, 1.0),
            ),
            activity: departure < .8
                ? FriendActivity.packing
                : FriendActivity.walking,
            facingRight: door.x >= origin.x,
            backpack: true,
            opacity: departure < 3.5
                ? 1
                : ((4 - departure) / .5).clamp(0.0, 1.0),
          );
          moment = RoomMoment.departing;
        } else {
          pose = FriendPose(
            kind: kind,
            position: door,
            activity: FriendActivity.away,
            opacity: 0,
          );
          moment = RoomMoment.waybiAway;
        }
      } else if (kind == traveller && arrival >= 0 && arrival < 4) {
        final target = _ambient(kind, seconds + 4 - arrival).position;
        pose = FriendPose(
          kind: kind,
          position: door.towards(target, arrival / 4),
          facingRight: target.x >= door.x,
          activity: FriendActivity.walking,
          backpack: true,
        );
        moment = RoomMoment.returning;
      } else if (pose.activity == FriendActivity.playing) {
        moment = RoomMoment.playing;
      } else if (moment == RoomMoment.waking) {
        if (kind == FriendKind.clover) {
          moment = pose.moving
              ? RoomMoment.cloverWalking
              : pose.activity == FriendActivity.watching
              ? RoomMoment.atWindow
              : pose.activity == FriendActivity.sleeping
              ? RoomMoment.napping
              : RoomMoment.waking;
        } else if (kind == FriendKind.sett && pose.moving) {
          moment = RoomMoment.exploring;
        }
      }
      poses.add(pose);
    }
    return RoomFrame(poses, moment, seconds);
  }
}
