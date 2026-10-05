import 'place_sources_sheet.dart';
import 'companion_search_prompt.dart';
import '../theme/waybi_theme.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/search_history_store.dart';
import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import '../providers/provider_contracts.dart';

class FullScreenSearch extends StatefulWidget {
  const FullScreenSearch({
    super.key,
    required this.provider,
    required this.resolve,
    required this.language,
    required this.recent,
    this.currentLocation,
    this.initialQuery = '',
    this.purpose,
    this.onDriveMode,
    this.marker = LocationMarkerStyle.kiwi,
  });

  final SearchProvider provider;
  final Future<PlaceSummary> Function(PlaceCandidate) resolve;
  final String language;
  final List<PlaceSummary> recent;
  final GeoPoint? currentLocation;
  final String initialQuery;
  final String? purpose;
  final VoidCallback? onDriveMode;
  final LocationMarkerStyle marker;

  @override
  State<FullScreenSearch> createState() => _FullScreenSearchState();
}

class _FullScreenSearchState extends State<FullScreenSearch> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );
  Timer? _debounce;
  int _request = 0;
  bool _loading = false;
  bool _resolving = false;
  bool _expandedArea = false;
  String? _error;
  List<PlaceCandidate> _results = const [];
  List<String> _recentQueries = const [];
  final SearchHistoryStore _history = SearchHistoryStore();

  String _text(String en, String zh) => widget.language == 'zh' ? zh : en;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
    if (widget.initialQuery.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search(widget.initialQuery);
      });
    }
  }

  Future<void> _loadHistory() async {
    try {
      final history = await _history.load();
      if (!mounted) return;
      setState(() => _recentQueries = history);
    } catch (_) {
      // Search must stay usable even if local preferences are unavailable.
    }
  }

  Future<void> _rememberQuery(String query) async {
    try {
      final history = await _history.remember(query);
      if (!mounted) return;
      setState(() => _recentQueries = history);
    } catch (_) {
      // History is an enhancement, never a blocker for search.
    }
  }

  Future<void> _removeRecentQuery(String query) async {
    try {
      final history = await _history.remove(query);
      if (!mounted) return;
      setState(() => _recentQueries = history);
    } catch (_) {
      // Ignore storage failures and keep the search surface responsive.
    }
  }

  void _useRecentQuery(String query) {
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _search(query, immediate: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _search(
    String input, {
    bool immediate = false,
    bool expandedArea = false,
  }) {
    _debounce?.cancel();
    final request = ++_request;
    final query = input.trim();
    if (query.runes.length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _expandedArea = expandedArea;
      // Keep the previous suggestions visible while the next prefix is
      // loading so typeahead never flashes to an empty state.
    });
    _debounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 160),
      () async {
        try {
          final provider = widget.provider;
          final results = expandedArea && provider is ExpandedSearchProvider
              ? await provider.searchFurther(
                  query,
                  proximity: widget.currentLocation,
                  language: widget.language,
                )
              : await provider.search(
                  query,
                  proximity: widget.currentLocation,
                  language: widget.language,
                );
          if (!mounted || request != _request) return;
          setState(() {
            _results = results;
            _loading = false;
          });
        } catch (_) {
          if (!mounted || request != _request) return;
          setState(() {
            _results = const [];
            _loading = false;
            _error = _text('Search is temporarily unavailable', '搜索暂不可用');
          });
        }
      },
    );
  }

  Future<void> _choose(PlaceCandidate candidate) async {
    if (_resolving) return;
    unawaited(_rememberQuery(_controller.text));
    setState(() => _resolving = true);
    try {
      final place = await widget.resolve(candidate);
      if (!mounted) return;
      Navigator.of(context).pop(place);
    } catch (_) {
      if (mounted) {
        setState(() {
          _resolving = false;
          _error = _text('Could not open this place', '无法打开此地点');
        });
      }
    }
  }

  String _distance(GeoPoint? point) {
    final from = widget.currentLocation;
    if (point == null || from == null) return '';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final recent = _controller.text.trim().isEmpty;
    final items = recent
        ? widget.recent
              .map(
                (place) => PlaceCandidate(
                  name: place.name,
                  address: place.address,
                  category: place.category,
                  kind: place.kind,
                  location: place.location,
                  reference: place.reference,
                ),
              )
              .toList(growable: false)
        : _results;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        bottom: widget.purpose == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(30),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(widget.purpose!),
                ),
              ),
        backgroundColor: theme.scaffoldBackgroundColor,
        titleSpacing: 0,
        title: Material(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(22),
          child: TextField(
            controller: _controller,
            autofocus: true,
            enableSuggestions: true,
            autocorrect: false,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(
                  color: WaybiColors.sky,
                  width: 1.3,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(
                  color: WaybiColors.sky,
                  width: 1.3,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(
                  color: WaybiColors.ocean,
                  width: 1.8,
                ),
              ),
              hintText: _text('Where to?', '去哪里？'),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(8),
                child: CompanionAvatar(marker: widget.marker, size: 32),
              ),
            ),
            onChanged: _search,
            onSubmitted: (value) {
              unawaited(_rememberQuery(value));
              _search(value, immediate: true);
            },
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              onPressed: () {
                _controller.clear();
                _search('');
              },
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loading || _resolving)
            const LinearProgressIndicator(minHeight: 2),
          if (!recent &&
              widget.provider is ExpandedSearchProvider &&
              widget.currentLocation != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 10, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _expandedArea
                          ? _text('All regions', '所有地区')
                          : _text('Nearby first', '附近优先'),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _loading
                        ? null
                        : () => _search(
                            _controller.text,
                            immediate: true,
                            expandedArea: !_expandedArea,
                          ),
                    icon: Icon(
                      _expandedArea
                          ? Icons.near_me_outlined
                          : Icons.public_rounded,
                      size: 17,
                    ),
                    label: Text(
                      _expandedArea
                          ? _text('Search nearby', '搜索附近')
                          : _text('Search further', '搜索更远的地点'),
                    ),
                  ),
                ],
              ),
            ),
          if (recent && _recentQueries.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
              child: Text(
                _text('Recent searches', '最近搜索'),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final query in _recentQueries)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                leading: const Icon(Icons.history_rounded),
                title: Text(
                  query,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: _text('Remove', '删除'),
                  onPressed: () => unawaited(_removeRecentQuery(query)),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
                onTap: () => _useRecentQuery(query),
              ),
          ],
          if (recent && items.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                _recentQueries.isEmpty ? 22 : 12,
                18,
                8,
              ),
              child: Text(
                _text('Recent places', '最近地点'),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (!recent && items.isNotEmpty && !_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
              child: Text(
                _text('Suggestions', '搜索联想'),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_error!, style: TextStyle(color: scheme.error)),
                  ),
                  TextButton(
                    onPressed: () => _search(
                      _controller.text,
                      immediate: true,
                      expandedArea: _expandedArea,
                    ),
                    child: Text(_text('Retry', '重试')),
                  ),
                ],
              ),
            ),
          if (recent && widget.onDriveMode != null)
            ListTile(
              leading: const Icon(Icons.directions_car_filled_rounded),
              title: Text(_text('Just Drive', '自由驾驶')),
              subtitle: Text(
                _text(
                  'Safety camera alerts without a destination',
                  '无需目的地也可接收摄像头提醒',
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                widget.onDriveMode?.call();
              },
            ),
          if (!recent &&
              !_loading &&
              !_resolving &&
              _error == null &&
              items.isEmpty &&
              _controller.text.trim().runes.length >= 2)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                _text(
                  'No places found. Try a street, address or local place name.',
                  '没有找到地点，试试街道、地址或当地地点名称。',
                ),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                final distance = _distance(item.location);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                  leading: Icon(
                    item.kind == PlaceKind.address
                        ? Icons.signpost_outlined
                        : Icons.place_outlined,
                    color: scheme.primary,
                  ),
                  title: Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: item.secondaryAddress.isEmpty
                      ? null
                      : Text(
                          item.secondaryAddress,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: distance.isEmpty
                      ? null
                      : Text(
                          distance,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                  onTap: () => _choose(item),
                );
              },
            ),
          ),
          if (items.any((item) {
            final provider = item.reference?.provider ?? '';
            return provider == 'google' ||
                provider == 'osm' ||
                provider == 'geoapify' ||
                provider == 'here' ||
                provider.startsWith('regional:');
          }))
            SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.info_outline_rounded),
                  tooltip: widget.language == 'zh' ? '数据来源' : 'Data credits',
                  onPressed: () {
                    final providerIds = items
                        .map((item) => item.reference?.provider ?? '')
                        .where((provider) => provider.isNotEmpty)
                        .toList(growable: false);
                    showPlaceSources(
                      context,
                      language: widget.language,
                      mapCompatible: !providerIds.contains('google'),
                      providerIds: providerIds,
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
