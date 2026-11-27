import '../theme/waybi_theme.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:http/http.dart' as http;

import '../data/api_config.dart';
import '../domain/geo_math.dart';
import 'waybi_format.dart';

class DestinationSuggestion {
  const DestinationSuggestion({
    required this.label,
    required this.location,
    this.name,
    this.address,
    this.isPoi,
  });
  final String label;
  final LatLng location;
  final String? name;
  final String? address;
  final bool? isPoi;
}

class ExploreSearch extends StatefulWidget {
  const ExploreSearch({
    super.key,
    required this.currentLocation,
    required this.onSelected,
    this.origin,
    this.onOriginSelected,
    this.onFocusChanged,
    this.recent = const [],
    this.language = 'en',
    this.destinationOnly = false,
    this.autofocus = false,
    this.initialQuery,
    this.resultsMaxHeight = 260,
  });

  final LatLng? currentLocation;
  final ValueChanged<DestinationSuggestion> onSelected;
  final DestinationSuggestion? origin;
  final ValueChanged<DestinationSuggestion?>? onOriginSelected;
  final ValueChanged<bool>? onFocusChanged;
  final List<DestinationSuggestion> recent;
  final String language;
  final bool destinationOnly;
  final bool autofocus;
  final String? initialQuery;
  final double resultsMaxHeight;

  @override
  State<ExploreSearch> createState() => _ExploreSearchState();
}

class _ExploreSearchState extends State<ExploreSearch> {
  final _controller = TextEditingController();
  final _originController = TextEditingController();
  final _destinationFocus = FocusNode();
  final _originFocus = FocusNode();
  bool _editingOrigin = false;
  final _client = http.Client();
  Timer? _debounce;
  DateTime? _suggestRetryAfter;
  List<DestinationSuggestion> _results = const [];
  String? _error;
  int _request = 0;
  // Null until a reverse lookup names the current place.
  String? _locationLabel;
  LatLng? _lastReverseLocation;
  bool _reverseLookupPending = false;

  bool get _isChinese => widget.language == 'zh';
  String _text(String english, String chinese) =>
      _isChinese ? chinese : english;

  String _distanceLabel(DestinationSuggestion result) {
    final current = widget.currentLocation;
    if (current == null) return '';
    final metres = distanceMeters(
      current.latitude,
      current.longitude,
      result.location.latitude,
      result.location.longitude,
    );
    return formatDistance(metres, widget.language);
  }

  @override
  void initState() {
    super.initState();
    _destinationFocus.addListener(_focusChanged);
    _originFocus.addListener(_focusChanged);
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _controller.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search(initial, origin: false);
      });
    }
    unawaited(_refreshCurrentLocationLabel(widget.currentLocation));
  }

  @override
  void didUpdateWidget(covariant ExploreSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = widget.currentLocation;
    final previous = _lastReverseLocation;
    if (current == null) {
      if (_locationLabel != null) setState(() => _locationLabel = null);
      return;
    }
    final moved = previous == null
        ? double.infinity
        : distanceMeters(
            previous.latitude,
            previous.longitude,
            current.latitude,
            current.longitude,
          );
    if (moved >= 120) {
      unawaited(_refreshCurrentLocationLabel(current));
    }
  }

  void _focusChanged() {
    if (_originFocus.hasFocus) _editingOrigin = true;
    if (_destinationFocus.hasFocus) _editingOrigin = false;
    widget.onFocusChanged?.call(
      _originFocus.hasFocus || _destinationFocus.hasFocus,
    );
    if (mounted) setState(() {});
  }

  Future<void> _refreshCurrentLocationLabel(LatLng? location) async {
    if (location == null || _reverseLookupPending) return;
    _reverseLookupPending = true;
    _lastReverseLocation = location;
    try {
      final uri = Uri.parse('$workerBaseUrl/api/reverse').replace(
        queryParameters: {'at': '${location.longitude},${location.latitude}'},
      );
      final response = await _client.get(uri);
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(response.body);
      final label = decoded is Map<String, dynamic>
          ? decoded['label']?.toString().trim()
          : null;
      if (!mounted || label == null || label.isEmpty) return;
      setState(() => _locationLabel = label);
    } catch (_) {
      // Keep the last readable place if reverse lookup is temporarily unavailable.
    } finally {
      _reverseLookupPending = false;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _originController.dispose();
    _destinationFocus.dispose();
    _originFocus.dispose();
    _client.close();
    super.dispose();
  }

  void _search(String text, {required bool origin}) {
    _editingOrigin = origin;
    _debounce?.cancel();
    final request = ++_request;
    final query = text.trim();
    if (query.runes.length < 2) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final near = widget.currentLocation;
        final params = {
          'q': query,
          'lang': widget.language,
          'provider': 'independent',
          if (near != null) 'near': '${near.longitude},${near.latitude}',
        };
        final suggestUri = Uri.parse('$workerBaseUrl/api/suggest')
            .replace(queryParameters: params);
        final fallbackUri = Uri.parse('$workerBaseUrl/api/search')
            .replace(queryParameters: params);
        final canTrySuggest =
            _suggestRetryAfter == null ||
            DateTime.now().isAfter(_suggestRetryAfter!);
        http.Response? response;
        if (canTrySuggest) {
          response = await _client.get(suggestUri);
          if (response.statusCode == 503 || response.statusCode == 502) {
            _suggestRetryAfter = DateTime.now().add(
              const Duration(seconds: 20),
            );
            response = null;
          } else if (response.statusCode == 200) {
            _suggestRetryAfter = null;
          }
        }
        response ??= await _client.get(fallbackUri);
        if (response.statusCode != 200) {
          throw StateError('Address search unavailable');
        }
        var decoded = jsonDecode(response.body) as List<dynamic>;
        // A provider can be healthy but return nothing for a niche POI/address.
        // Fall back for this query only; never permanently downgrade the session.
        if (decoded.isEmpty &&
            response.request?.url.path.endsWith('/suggest') == true) {
          final fallback = await _client.get(fallbackUri);
          if (fallback.statusCode == 200) {
            decoded = jsonDecode(fallback.body) as List<dynamic>;
          }
        }
        final places = decoded
            .whereType<Map<String, dynamic>>()
            .map((item) {
              final latitude = item['latitude'];
              final longitude = item['longitude'];
              if (latitude is! num || longitude is! num) return null;
              final label =
                  item['label']?.toString() ??
                  _text('Selected destination', '所选目的地');
              return DestinationSuggestion(
                label: label,
                name: item['name']?.toString().trim().isNotEmpty == true
                    ? item['name'].toString().trim()
                    : label,
                address: item['address']?.toString().trim(),
                isPoi: item['isPoi'] is bool ? item['isPoi'] as bool : null,
                location: LatLng(
                  latitude: latitude.toDouble(),
                  longitude: longitude.toDouble(),
                ),
              );
            })
            .whereType<DestinationSuggestion>()
            .toList();
        final deduped = <DestinationSuggestion>[];
        final seen = <String>{};
        for (final place in places) {
          final key = [
            (place.address?.trim().isNotEmpty == true
                    ? place.address!
                    : place.label)
                .toLowerCase()
                .replaceAll(RegExp(r'[^a-z0-9\p{L}]+', unicode: true), ''),
            place.location.latitude.toStringAsFixed(4),
            place.location.longitude.toStringAsFixed(4),
          ].join('|');
          if (seen.add(key)) deduped.add(place);
        }
        if (!mounted || request != _request) return;
        setState(() {
          _results = deduped;
          _error = null;
        });
      } catch (_) {
        if (!mounted || request != _request) return;
        setState(() {
          _results = const [];
          _error = _text('Address search is unavailable', '地址搜索暂不可用');
        });
      }
    });
  }

  void _clearDestination() {
    _debounce?.cancel();
    _request++;
    _controller.clear();
    setState(() {
      _results = const [];
      _error = null;
    });
    _destinationFocus.requestFocus();
  }

  void _clearOrigin() {
    _debounce?.cancel();
    _request++;
    _originController.clear();
    setState(() {
      _results = const [];
      _error = null;
    });
    widget.onOriginSelected?.call(null);
    _originFocus.requestFocus();
  }

  String _resultTitle(DestinationSuggestion result) {
    final address = result.address?.trim() ?? '';
    final name = result.name?.trim() ?? '';
    if (result.isPoi == false && address.isNotEmpty) {
      final first = address.split(',').first.trim();
      if (first.isNotEmpty) return first;
    }
    if (name.isNotEmpty) return name;
    return result.label;
  }

  String _resultAddress(DestinationSuggestion result) {
    final address = result.address?.trim() ?? '';
    if (address.isEmpty) return '';
    final title = _resultTitle(result);
    if (address == title) return result.label == title ? '' : result.label;
    final prefix = '$title,';
    if (address.toLowerCase().startsWith(prefix.toLowerCase())) {
      final locality = address.substring(prefix.length).trim();
      if (locality.isNotEmpty) return locality;
    }
    return address;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final location = widget.currentLocation;
    final locationText = location == null || _locationLabel == null
        ? _text('Locating current position…', '正在定位当前位置…')
        : _locationLabel!;
    return Material(
      color: scheme.surface,
      elevation: 11,
      borderRadius: BorderRadius.circular(21),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
            child: Column(
              children: [
                if (!widget.destinationOnly)
                  Row(
                    children: [
                      Icon(
                        Icons.my_location_rounded,
                        size: 19,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _originController,
                              focusNode: _originFocus,
                              onChanged: (value) {
                                setState(() {});
                                _search(value, origin: true);
                              },
                              decoration: InputDecoration(
                                isDense: true,
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                hintText: widget.origin?.label ?? locationText,
                                hintStyle: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: WaybiTextSize.caption,
                                ),
                                suffixIconConstraints: const BoxConstraints(
                                  minWidth: 34,
                                  minHeight: 34,
                                ),
                                suffixIcon: _originController.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: _text('Clear', '清空'),
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          size: 18,
                                        ),
                                        onPressed: _clearOrigin,
                                      ),
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                if (!widget.destinationOnly) const Divider(height: 19),
                Row(
                  children: [
                    Semantics(
                      label: _text('Destination', '目的地'),
                      child: Container(
                        key: const Key('destinationSearchIcon'),
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: WaybiColors.sky,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: WaybiColors.ocean,
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: WaybiColors.deepOcean,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _destinationFocus,
                        autofocus: widget.autofocus,
                        onChanged: (value) {
                          setState(() {});
                          _search(value, origin: false);
                        },
                        decoration: InputDecoration(
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: _text('Where to?', '想去哪？'),
                          hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          suffixIcon: _controller.text.isEmpty
                              ? Icon(
                                  Icons.search_rounded,
                                  color: scheme.primary,
                                )
                              : IconButton(
                                  key: const Key('destinationClearButton'),
                                  tooltip: _text('Clear', '清空'),
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 20,
                                  ),
                                  onPressed: _clearDestination,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(
                  color: scheme.error,
                  fontSize: WaybiTextSize.caption,
                ),
              ),
            ),
          if (_results.isNotEmpty ||
              ((_destinationFocus.hasFocus || widget.destinationOnly) &&
                  _controller.text.isEmpty &&
                  widget.recent.isNotEmpty))
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: widget.resultsMaxHeight),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _results.isNotEmpty
                    ? _results.length
                    : widget.recent.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final result = _results.isNotEmpty
                      ? _results[index]
                      : widget.recent[index];
                  final address = _resultAddress(result);
                  final distance = _distanceLabel(result);
                  final title = _resultTitle(result);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    leading: Icon(Icons.place_outlined, color: scheme.primary),
                    title: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: address.isEmpty && distance.isEmpty
                        ? null
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (address.isNotEmpty)
                                Text(
                                  address,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (distance.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    distance,
                                    style: TextStyle(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                    onTap: () {
                      _debounce?.cancel();
                      _request++;
                      if (_editingOrigin) {
                        _originController.text = title;
                      } else {
                        _controller.text = title;
                      }
                      FocusScope.of(context).unfocus();
                      setState(() => _results = const []);
                      if (_editingOrigin) {
                        widget.onOriginSelected?.call(result);
                      } else {
                        widget.onSelected(result);
                      }
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
