import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/map_provider.dart';
import '../theme/waybi_theme.dart';
import 'waybi_bird.dart';

String companionName(LocationMarkerStyle marker) => switch (marker) {
  LocationMarkerStyle.cat => 'Clover',
  LocationMarkerStyle.dog => 'Sett',
  _ => 'Waybi',
};

class CompanionAvatar extends StatelessWidget {
  const CompanionAvatar({super.key, required this.marker, this.size = 48});

  final LocationMarkerStyle marker;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (marker != LocationMarkerStyle.cat &&
        marker != LocationMarkerStyle.dog) {
      return WaybiBird(size: size);
    }
    final cat = marker == LocationMarkerStyle.cat;
    return Semantics(
      label: companionName(marker),
      image: true,
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * .06),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cat ? const Color(0xFFFFE0E5) : const Color(0xFFDDF2FF),
        ),
        child: Image.asset(
          'assets/markers/${cat ? 'clover' : 'sett'}.png',
          fit: BoxFit.contain,
          cacheWidth: (size * 3).ceil(),
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

/// A short greeting when the search prompt appears or the companion changes.
/// The animation finishes, leaving no continuously running ticker over the map.
class CompanionSearchPrompt extends StatefulWidget {
  const CompanionSearchPrompt({
    super.key,
    required this.marker,
    required this.language,
    required this.onTap,
  });

  final LocationMarkerStyle marker;
  final String language;
  final VoidCallback onTap;

  @override
  State<CompanionSearchPrompt> createState() => _CompanionSearchPromptState();
}

class _CompanionSearchPromptState extends State<CompanionSearchPrompt>
    with SingleTickerProviderStateMixin {
  late final _greeting = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _greet();
  }

  void _greet() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _greeting.stop();
      _greeting.value = 1;
    } else {
      _greeting.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant CompanionSearchPrompt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.marker != widget.marker) _greet();
  }

  @override
  void dispose() {
    _greeting.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chinese = widget.language == 'zh';
    final name = companionName(widget.marker);
    final question = chinese ? '去哪里？' : 'Where to?';
    return Semantics(
      button: true,
      label: '$name: $question',
      excludeSemantics: true,
      child: Material(
        color: scheme.surface.withValues(alpha: .96),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(19),
          side: BorderSide(color: scheme.primary.withValues(alpha: .25)),
        ),
        elevation: 4,
        shadowColor: const Color(0x3020351C),
        child: InkWell(
          key: const Key('companionSearchButton'),
          borderRadius: BorderRadius.circular(19),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(9, 8, 12, 8),
            child: Row(
              children: [
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _greeting,
                    child: CompanionAvatar(marker: widget.marker),
                    builder: (context, child) {
                      final wave = math.sin(_greeting.value * math.pi * 4);
                      final envelope = 1 - _greeting.value;
                      return Transform.translate(
                        offset: Offset(0, -2 * wave.abs() * envelope),
                        child: Transform.rotate(
                          angle: .055 * wave * envelope,
                          child: Transform.scale(
                            scale: 1 + .04 * wave.abs() * envelope,
                            child: child,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        question,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        chinese ? '$name 陪你出发' : '$name is ready when you are',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: WaybiColors.ocean,
                  size: 19,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
