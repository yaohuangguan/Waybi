import 'package:flutter/material.dart';

import '../theme/waybi_theme.dart';
import 'waybi_format.dart';

/// A regulatory speed-limit roundel (red ring, white disc, black numerals),
/// as on New Zealand and Australian roads. It reads the same on any map or
/// theme, so its colours are fixed rather than themed.
class SpeedLimitSign extends StatelessWidget {
  const SpeedLimitSign({
    super.key,
    required this.limitKph,
    this.language,
    this.size = 52,
  });

  /// The posted limit, or null when it is unknown.
  final int? limitKph;
  final String? language;
  final double size;

  static const ring = Color(0xFFD0021B);
  static const disc = Color(0xFFFFFFFF);
  static const numeral = Color(0xFF111111);
  static const unknownRing = Color(0xFF8A9384);

  @override
  Widget build(BuildContext context) {
    final lang = waybiLanguageOf(context, language);
    final limit = limitKph;
    final label = limit == null
        ? (lang == 'zh' ? '限速未知' : 'Speed limit unknown')
        : (lang == 'zh'
              ? '限速 $limit ${speedUnit(lang)}'
              : 'Speed limit $limit ${speedUnit(lang)}');
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: SizedBox.square(
        key: const ValueKey('speedLimitSign'),
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: disc,
            shape: BoxShape.circle,
            border: Border.all(
              color: limit == null ? unknownRing : ring,
              width: size * .12,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 6),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(size * .15),
            child: FittedBox(
              child: Text(
                limit?.toString() ?? '—',
                textScaler: TextScaler.noScaling,
                style: const TextStyle(
                  color: numeral,
                  fontSize: 24,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Current speed on an always-dark guidance surface. Over the limit, the
/// value turns red *and* gains a warning icon and spoken state, so the
/// warning does not rely on colour alone.
class CurrentSpeedReadout extends StatelessWidget {
  const CurrentSpeedReadout({
    super.key,
    required this.speedKph,
    required this.speeding,
    this.language,
    this.framed = true,
    this.width = 88,
  });

  final double speedKph;
  final bool speeding;
  final String? language;

  /// Draw the bordered tile; without it the readout sits inside another bar.
  final bool framed;
  final double width;

  @override
  Widget build(BuildContext context) {
    final lang = waybiLanguageOf(context, language);
    final type = context.driveType;
    final speed = speedKph.isFinite ? speedKph.round().clamp(0, 999) : 0;
    final colour = speeding ? WaybiInk.danger : WaybiInk.accent;
    final label = lang == 'zh'
        ? '当前速度 $speed ${speedUnit(lang)}${speeding ? '，已超速' : ''}'
        : 'Speed $speed ${speedUnit(lang)}${speeding ? ', over the limit' : ''}';
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (speeding) ...[
              const Icon(
                Icons.warning_rounded,
                key: ValueKey('overSpeedIcon'),
                color: WaybiInk.danger,
                size: 18,
              ),
              const SizedBox(width: 2),
            ],
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$speed',
                  style: type.value.copyWith(color: colour, fontSize: 28),
                ),
              ),
            ),
          ],
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            speedUnit(lang),
            style: type.unit.copyWith(color: WaybiInk.muted),
          ),
        ),
      ],
    );
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: framed
          ? Container(
              key: const ValueKey('currentSpeedReadout'),
              width: width,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              decoration: BoxDecoration(
                color: WaybiInk.surface,
                border: Border.all(
                  color: speeding ? WaybiInk.danger : WaybiInk.text,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(color: Color(0x33000000), blurRadius: 14),
                ],
              ),
              child: content,
            )
          : content,
    );
  }
}
