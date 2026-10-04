import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'character_rig.dart';
import 'friend_strings.dart';
import 'room_life.dart';
import 'theme.dart';

class LivingRoomScene extends StatefulWidget {
  const LivingRoomScene({
    super.key,
    required this.life,
    required this.waybiAway,
    required this.onWaybiTap,
    required this.onCloverTap,
    required this.onSettTap,
    this.thought,
    this.thoughtUntil,
    this.clock,
    this.animate = true,
  });
  final RoomLife life;
  final bool waybiAway;
  final VoidCallback onWaybiTap, onCloverTap, onSettTap;
  final String? thought;
  final DateTime? thoughtUntil;
  final DateTime Function()? clock;
  final bool animate;

  @override
  State<LivingRoomScene> createState() => _LivingRoomSceneState();
}

class _LivingRoomSceneState extends State<LivingRoomScene>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _frames;
  Timer? _quietTick;
  bool _foreground = true;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _frames = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    _quietTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          _foreground &&
          TickerMode.valuesOf(context).enabled &&
          _reduced &&
          widget.animate) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    _scheduleFrames();
  }

  @override
  void didUpdateWidget(covariant LivingRoomScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleFrames();
  }

  void _scheduleFrames() {
    final active =
        widget.animate &&
        !_reduced &&
        _foreground &&
        TickerMode.valuesOf(context).enabled;
    if (active && !_frames.isAnimating) _frames.repeat();
    if (!active && _frames.isAnimating) _frames.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _scheduleFrames();
    if (_foreground && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _quietTick?.cancel();
    _frames.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: AnimatedBuilder(
        animation: _frames,
        builder: (context, _) {
          final now = (widget.clock ?? DateTime.now)();
          final frame = widget.life.sample(now, waybiAway: widget.waybiAway);
          final poses = frame.friends.where((p) => p.opacity > 0).toList()
            ..sort((a, b) => a.position.y.compareTo(b.position.y));
          final thoughtActive =
              widget.thought != null &&
              widget.thoughtUntil != null &&
              now.isBefore(widget.thoughtUntil!);
          return LayoutBuilder(
            builder: (context, bounds) {
              final w = bounds.maxWidth, h = bounds.maxHeight;
              final characterWidth = (w * .27).clamp(68.0, 116.0);
              return Stack(
                fit: StackFit.expand,
                children: [
                  const CustomPaint(painter: _LivingRoomPainter()),
                  Positioned(
                    top: 17,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: WwhColors.paper.withValues(alpha: .94),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        thoughtActive
                            ? widget.thought!
                            : roomCaption(context, frame.moment),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: WwhColors.ink,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                  for (final pose in poses)
                    Positioned(
                      key: ValueKey('friend-position-${pose.kind.name}'),
                      left: pose.position.x * w - characterWidth / 2,
                      top: pose.position.y * h - characterWidth,
                      child: Opacity(
                        opacity: pose.opacity,
                        child: Semantics(
                          label:
                              '${_name(pose.kind)}, ${_activity(context, pose.activity)}',
                          button: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: switch (pose.kind) {
                              FriendKind.waybi => widget.onWaybiTap,
                              FriendKind.clover => widget.onCloverTap,
                              FriendKind.sett => widget.onSettTap,
                            },
                            child: SizedBox(
                              width: characterWidth,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: characterWidth,
                                    height: characterWidth,
                                    child: CustomPaint(
                                      key: ValueKey(
                                        'friend-rig-${pose.kind.name}',
                                      ),
                                      painter: CharacterRig(
                                        pose: pose,
                                        seconds:
                                            frame.seconds +
                                            pose.kind.index * .63,
                                        reducedMotion: _reduced,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: WwhColors.paper.withValues(
                                        alpha: .9,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      _name(pose.kind),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: WwhColors.ink,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (widget.waybiAway &&
                      frame.friend(FriendKind.waybi).opacity == 0)
                    Positioned(
                      right: 12,
                      bottom: 17,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.flight_takeoff_rounded,
                            size: 13,
                            color: WwhColors.moss,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            friendText(
                              context,
                              'Waybi is exploring',
                              'Waybi 在外探索',
                            ),
                            style: const TextStyle(
                              color: WwhColors.moss,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    ),
  );

  String _name(FriendKind kind) => switch (kind) {
    FriendKind.waybi => 'Waybi',
    FriendKind.clover => 'Clover',
    FriendKind.sett => 'Sett',
  };
  String _activity(BuildContext context, FriendActivity activity) =>
      switch (activity) {
        FriendActivity.walking => friendText(context, 'walking', '散步中'),
        FriendActivity.running => friendText(context, 'running', '小跑中'),
        FriendActivity.sleeping => friendText(context, 'sleeping', '睡觉中'),
        FriendActivity.watching => friendText(context, 'looking out', '看风景'),
        FriendActivity.packing => friendText(context, 'ready to leave', '准备出门'),
        FriendActivity.away => friendText(context, 'exploring', '探索中'),
        _ => friendText(context, 'at home', '在家里'),
      };
}

class _LivingRoomPainter extends CustomPainter {
  const _LivingRoomPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    void box(Rect rect, Color color, [double radius = 0]) => canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()..color = color,
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF0E8D7),
    );
    box(Rect.fromLTWH(0, h * .61, w, h * .39), const Color(0xFFDDB991));
    box(Rect.fromLTWH(0, h * .605, w, 6), const Color(0xFFCBA87D));
    final planks = Paint()
      ..color = const Color(0x249A714C)
      ..strokeWidth = 1;
    for (double y = h * .67; y < h; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(w, y), planks);
    }
    for (var row = 0; row < 6; row++) {
      final y = h * .67 + row * 28;
      if (y > h) break;
      for (double x = row.isEven ? w * .2 : w * .45; x < w; x += w * .52) {
        canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 28, h)), planks);
      }
    }
    final sunbeam = Path()
      ..moveTo(w * .37, h * .58)
      ..lineTo(w * .67, h * .58)
      ..lineTo(w * .9, h * .98)
      ..lineTo(w * .35, h * .98)
      ..close();
    canvas.drawPath(sunbeam, Paint()..color = const Color(0x25FFF6CD));

    final window = Rect.fromLTWH(w * .34, h * .22, w * .34, h * .31);
    box(window.inflate(7), const Color(0xFFCBB58D), 12);
    box(window, const Color(0xFFBDDFE1), 9);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(window, const Radius.circular(9)));
    canvas.drawCircle(
      Offset(w * .6, h * .29),
      w * .032,
      Paint()..color = const Color(0xFFFFEDB1),
    );
    final hill = Path()
      ..moveTo(window.left, window.bottom - h * .045)
      ..quadraticBezierTo(w * .43, h * .4, w * .52, h * .49)
      ..quadraticBezierTo(w * .62, h * .42, window.right, h * .49)
      ..lineTo(window.right, window.bottom)
      ..lineTo(window.left, window.bottom)
      ..close();
    canvas.drawPath(hill, Paint()..color = const Color(0xFF9BB77B));
    canvas.restore();
    final frame = Paint()
      ..color = WwhColors.paper
      ..strokeWidth = 5;
    canvas.drawLine(
      Offset(w * .51, window.top),
      Offset(w * .51, window.bottom),
      frame,
    );
    canvas.drawLine(
      Offset(window.left, h * .37),
      Offset(window.right, h * .37),
      frame,
    );
    box(Rect.fromLTWH(w * .31, h * .535, w * .4, 8), WwhColors.paper, 3);
    box(
      Rect.fromLTWH(w * .31, h * .25, w * .025, h * .29),
      const Color(0xFFDBBDA3),
      5,
    );
    box(
      Rect.fromLTWH(w * .68, h * .25, w * .025, h * .29),
      const Color(0xFFDBBDA3),
      5,
    );

    box(
      Rect.fromLTWH(w * .83, h * .40, w * .17, h * .31),
      const Color(0xFFB49371),
      12,
    );
    box(
      Rect.fromLTWH(w * .848, h * .415, w * .15, h * .292),
      const Color(0xFFC9AC85),
      8,
    );
    canvas.drawCircle(
      Offset(w * .866, h * .60),
      3,
      Paint()..color = const Color(0xFF886749),
    );
    box(
      Rect.fromLTWH(w * .065, h * .605, w * .34, h * .155),
      const Color(0xFF85996E),
      18,
    );
    box(
      Rect.fromLTWH(w * .085, h * .56, w * .30, h * .115),
      const Color(0xFFA4B58C),
      16,
    );
    box(
      Rect.fromLTWH(w * .09, h * .67, w * .28, h * .06),
      const Color(0xFFBBCAA2),
      10,
    );
    box(
      Rect.fromLTWH(w * .055, h * .645, w * .065, h * .13),
      const Color(0xFF93A67A),
      10,
    );
    box(
      Rect.fromLTWH(w * .35, h * .645, w * .065, h * .13),
      const Color(0xFF93A67A),
      10,
    );
    box(Rect.fromLTWH(w * .11, h * .758, 6, 10), WwhColors.woodDark, 2);
    box(Rect.fromLTWH(w * .355, h * .758, 6, 10), WwhColors.woodDark, 2);
    canvas.save();
    canvas.translate(w * .18, h * .625);
    canvas.rotate(-.13);
    box(
      Rect.fromLTWH(-w * .04, -h * .03, w * .10, h * .065),
      const Color(0xFFF1DCC1),
      7,
    );
    canvas.restore();
    canvas.drawOval(
      Rect.fromLTWH(w * .29, h * .81, w * .45, h * .14),
      Paint()..color = const Color(0xFFC59D80),
    );
    canvas.drawOval(
      Rect.fromLTWH(w * .30, h * .815, w * .43, h * .125),
      Paint()..color = const Color(0xFFECD7BA),
    );
    box(
      Rect.fromLTWH(w * .11, h * .26, w * .15, h * .19),
      const Color(0xFFB99A71),
      4,
    );
    box(
      Rect.fromLTWH(w * .125, h * .272, w * .12, h * .16),
      const Color(0xFFF6EDDA),
      2,
    );
    canvas.drawCircle(
      Offset(w * .185, h * .325),
      w * .03,
      Paint()..color = const Color(0xFFD3DEB5),
    );
    box(
      Rect.fromLTWH(w * .73, h * .595, w * .07, h * .064),
      const Color(0xFFBF865F),
      5,
    );
    final leaf = Paint()..color = const Color(0xFF729260);
    for (final dx in [-.018, 0.0, .018]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w * (.765 + dx), h * .575),
          width: w * .033,
          height: h * .063,
        ),
        leaf,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LivingRoomPainter oldDelegate) => false;
}
