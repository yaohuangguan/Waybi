import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/map_provider.dart';
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
    required this.onSearch,
  });

  final LocationMarkerStyle marker;
  final String language;
  final ValueChanged<String> onSearch;

  @override
  State<CompanionSearchPrompt> createState() => _CompanionSearchPromptState();
}

class _CompanionSearchPromptState extends State<CompanionSearchPrompt>
    with SingleTickerProviderStateMixin {
  late final _greeting = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  final _input = TextEditingController();
  bool? _reduceMotion;

  void _submit() {
    FocusScope.of(context).unfocus();
    widget.onSearch(_input.text.trim());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion != reduced) {
      _reduceMotion = reduced;
      _greet();
    }
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
    _input.dispose();
    _greeting.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chinese = widget.language == 'zh';
    final name = companionName(widget.marker);
    final question = chinese ? '去哪里？' : 'Where to?';
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .65)),
      ),
      elevation: 3,
      shadowColor: const Color(0x2420351C),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _greeting,
                child: CompanionAvatar(marker: widget.marker, size: 44),
                builder: (context, child) {
                  final wave = math.sin(_greeting.value * math.pi * 4);
                  final envelope = 1 - _greeting.value;
                  return Transform.translate(
                    offset: Offset(0, -2 * wave.abs() * envelope),
                    child: Transform.rotate(
                      angle: .04 * wave * envelope,
                      child: child,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$name · $question',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  TextField(
                    key: const Key('companionSearchInput'),
                    controller: _input,
                    textInputAction: TextInputAction.search,
                    autocorrect: false,
                    style: TextStyle(color: scheme.onSurface, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: chinese
                          ? '搜索地点、地址'
                          : 'Search places or addresses',
                      hintStyle: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 15,
                      ),
                      isDense: true,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              key: const Key('companionSearchSubmit'),
              tooltip: chinese ? '搜索' : 'Search',
              onPressed: _submit,
              style: IconButton.styleFrom(
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.primary,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.search_rounded, size: 21),
            ),
          ],
        ),
      ),
    );
  }
}
