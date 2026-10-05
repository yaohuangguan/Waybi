import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/geo_math.dart';
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
    required this.loadSuggestions,
    required this.onSuggestionSelected,
    this.currentLocation,
  });

  final LocationMarkerStyle marker;
  final String language;
  final ValueChanged<String> onSearch;
  final Future<List<PlaceCandidate>> Function(String query) loadSuggestions;
  final ValueChanged<PlaceCandidate> onSuggestionSelected;
  final GeoPoint? currentLocation;

  @override
  State<CompanionSearchPrompt> createState() => _CompanionSearchPromptState();
}

class _CompanionSearchPromptState extends State<CompanionSearchPrompt>
    with SingleTickerProviderStateMixin {
  late final _greeting = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  bool? _reduceMotion;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  int _requestId = 0;
  bool _loading = false;
  List<PlaceCandidate> _suggestions = const [];

  void _onChanged(String raw) {
    _debounce?.cancel();
    final query = raw.trim();
    final request = ++_requestId;
    if (query.runes.length < 2) {
      setState(() {
        _loading = false;
        _suggestions = const [];
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 120), () async {
      try {
        final results = await widget.loadSuggestions(query);
        if (!mounted || request != _requestId) return;
        setState(() {
          _suggestions = results.take(4).toList(growable: false);
          _loading = false;
        });
      } catch (_) {
        if (!mounted || request != _requestId) return;
        setState(() => _loading = false);
      }
    });
  }

  String _distance(GeoPoint? point) {
    final from = widget.currentLocation;
    if (from == null || point == null) return '';
    final metres = distanceMeters(
      from.latitude,
      from.longitude,
      point.latitude,
      point.longitude,
    );
    return metres < 1000
        ? '${metres.round()} m'
        : '${(metres / 1000).toStringAsFixed(1)} km';
  }

  void _select(PlaceCandidate candidate) {
    _debounce?.cancel();
    _focusNode.unfocus();
    _controller.clear();
    setState(() => _suggestions = const []);
    widget.onSuggestionSelected(candidate);
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
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
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
                        controller: _controller,
                        focusNode: _focusNode,
                        style: TextStyle(color: scheme.onSurface, fontSize: 16),
                        textInputAction: TextInputAction.search,
                        autocorrect: false,
                        enableSuggestions: true,
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
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                        onChanged: _onChanged,
                        onSubmitted: (value) {
                          if (_suggestions.isNotEmpty) {
                            _select(_suggestions.first);
                          } else if (value.trim().isNotEmpty) {
                            widget.onSearch(value.trim());
                          }
                        },
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  key: const Key('companionSearchSubmit'),
                  tooltip: chinese ? '搜索' : 'Search',
                  onPressed: () {
                    final query = _controller.text.trim();
                    if (_suggestions.isNotEmpty) {
                      _select(_suggestions.first);
                    } else {
                      widget.onSearch(query);
                    }
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.search_rounded, size: 21),
                ),
              ],
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_suggestions.isNotEmpty) ...[
              const Divider(height: 8),
              for (final suggestion in _suggestions)
                InkWell(
                  key: ValueKey('mapSuggestion-${suggestion.name}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _select(suggestion),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Icon(
                          suggestion.kind == PlaceKind.address
                              ? Icons.signpost_outlined
                              : Icons.place_outlined,
                          size: 20,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                suggestion.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (suggestion.secondaryAddress.isNotEmpty ||
                                  suggestion.category == 'approximate_address')
                                Text(
                                  [
                                    if (suggestion.category ==
                                        'approximate_address')
                                      chinese
                                          ? '约略位置'
                                          : 'Approximate location',
                                    if (suggestion.secondaryAddress.isNotEmpty)
                                      suggestion.secondaryAddress,
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        finalDistance(suggestion.location, _distance),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

Widget finalDistance(GeoPoint? location, String Function(GeoPoint?) distance) {
  final value = distance(location);
  if (value.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(left: 8),
    child: Text(value, style: const TextStyle(fontSize: 11)),
  );
}
