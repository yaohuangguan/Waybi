import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';

import '../data/explore_repository.dart';
import '../domain/geo_math.dart';
import '../theme/waybi_theme.dart';
import 'waybi_bird.dart';
import 'place_sources_sheet.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({
    super.key,
    required this.currentLocation,
    required this.language,
    this.mapCompatible = false,
    this.repository,
  });

  final LatLng? currentLocation;
  final String language;
  final bool mapCompatible;
  final ExploreRepository? repository;

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  late final ExploreRepository _repository =
      widget.repository ?? ExploreRepository();
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  List<ExplorePlace> _places = const [];
  String _category = 'for-you';
  bool _loading = false;
  String? _error;
  int _request = 0;

  bool get _isChinese => widget.language == 'zh';
  String _text(String english, String chinese) =>
      _isChinese ? chinese : english;

  static const _categories = <(String, String, String, IconData)>[
    ('for-you', 'For you', '推荐', Icons.auto_awesome_rounded),
    ('food', 'Food', '美食', Icons.restaurant_rounded),
    ('coffee', 'Coffee', '咖啡', Icons.coffee_rounded),
    ('activities', 'Things to do', '玩乐', Icons.local_activity_rounded),
    ('shopping', 'Shopping', '购物', Icons.shopping_bag_rounded),
    ('parks', 'Parks', '公园', Icons.park_rounded),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ExplorePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentLocation == null && widget.currentLocation != null) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _repository.dispose();
    super.dispose();
  }

  void _searchChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    final query = value.trim();
    if (query.length == 1) return;
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_load(query: query));
    });
  }

  Future<void> _load({String? query}) async {
    final location = widget.currentLocation;
    if (location == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _text('Waiting for your location…', '正在获取你的位置…');
        });
      }
      return;
    }
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final places = await _repository.fetch(
        latitude: location.latitude,
        longitude: location.longitude,
        category: _category,
        language: widget.language,
        query: query ?? _search.text,
        mapCompatible: widget.mapCompatible,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _places = places;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = _text(
          'Could not load nearby places. Pull to retry.',
          '附近地点加载失败，下拉重试。',
        );
      });
    }
  }

  void _selectCategory(String value) {
    if (_category == value && _search.text.isEmpty) return;
    _debounce?.cancel();
    _search.clear();
    setState(() => _category = value);
    unawaited(_load(query: ''));
  }

  String _distance(ExplorePlace place) {
    final current = widget.currentLocation;
    if (current == null) return '';
    final metres = distanceMeters(
      current.latitude,
      current.longitude,
      place.latitude,
      place.longitude,
    );
    if (metres < 1000) return '${metres.round()} m';
    final km = metres / 1000;
    final value = km < 10 ? km.toStringAsFixed(1) : km.round().toString();
    return '$value km';
  }

  String _priceLabel(String? priceLevel) {
    return switch (priceLevel) {
      'PRICE_LEVEL_INEXPENSIVE' => r'$',
      'PRICE_LEVEL_MODERATE' => r'$$',
      'PRICE_LEVEL_EXPENSIVE' => r'$$$',
      'PRICE_LEVEL_VERY_EXPENSIVE' => r'$$$$',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: _text('Data & photo credits', '数据与图片来源'),
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () =>
                showPlaceSources(context, language: widget.language),
          ),
        ],
        title: Text(
          _text('Explore', '探索'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text('Discover something nearby', '看看附近有什么好玩的'),
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _text(
                        'Sights, green spaces, food and little local finds',
                        '风景、公园、美食，发现附近的小惊喜',
                      ),
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: _search,
                      onChanged: _searchChanged,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: _text(
                          'Search restaurants, museums, activities…',
                          '搜索餐厅、博物馆、玩乐地点…',
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: scheme.primary,
                        ),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: _text('Clear', '清空'),
                                onPressed: () {
                                  _debounce?.cancel();
                                  _search.clear();
                                  setState(() {});
                                  unawaited(_load(query: ''));
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                        filled: true,
                        fillColor: scheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: theme.dividerColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: theme.dividerColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(
                            color: scheme.primary,
                            width: 1.6,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 39,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _categories.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 7),
                        itemBuilder: (context, index) {
                          final item = _categories[index];
                          return ChoiceChip(
                            avatar: Icon(item.$4, size: 17),
                            label: Text(_text(item.$2, item.$3)),
                            selected: _category == item.$1,
                            onSelected: (_) => _selectCategory(item.$1),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: LinearProgressIndicator(),
                ),
              ),
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ),
              ),
            if (!_loading && _error == null && _places.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Center(
                    child: Text(
                      _text('No nearby places found.', '附近暂时没有找到合适地点。'),
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
              sliver: SliverList.separated(
                itemCount: _places.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final place = _places[index];
                  return _ExploreCard(
                    place: place,
                    distance: _distance(place),
                    price: _priceLabel(place.priceLevel),
                    language: widget.language,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExploreCard extends StatelessWidget {
  const _ExploreCard({
    required this.place,
    required this.distance,
    required this.price,
    required this.language,
  });
  final ExplorePlace place;
  final String distance;
  final String price;
  final String language;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final photo = place.photoUrl;
    final rating = place.rating;
    final isChinese = language == 'zh';
    return Material(
      color: scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(place),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (photo != null)
              SizedBox(
                height: 172,
                width: double.infinity,
                child: Image.network(
                  photo,
                  fit: BoxFit.cover,
                  cacheWidth: 800,
                  errorBuilder: (_, _, _) => _PhotoFallback(
                    category: place.primaryType,
                    language: language,
                  ),
                ),
              )
            else
              SizedBox(
                height: 116,
                width: double.infinity,
                child: _PhotoFallback(
                  category: place.primaryType,
                  language: language,
                ),
              ),
            if (place.photoCredit != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 10),
                  ),
                  onPressed: () => showPlaceSources(
                    context,
                    language: language,
                    photoCredit: place.photoCredit,
                  ),
                  icon: const Icon(Icons.photo_camera_outlined, size: 13),
                  label: Text(isChinese ? '图片来源' : 'Photo credit'),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 13, 15, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (rating != null)
                        Text(
                          '${rating.toStringAsFixed(1)} ★',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      if (place.userRatingCount != null)
                        Text('(${place.userRatingCount})'),
                      if (place.primaryType.isNotEmpty)
                        Text(exploreCategoryLabel(place.primaryType, language)),
                      if (price.isNotEmpty) Text(price),
                      if (distance.isNotEmpty)
                        Text(
                          distance,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      if (place.openNow != null)
                        Text(
                          place.openNow!
                              ? (isChinese ? '营业中' : 'Open now')
                              : (isChinese ? '已关闭' : 'Closed'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: place.openNow!
                                ? WaybiColors.success
                                : scheme.error,
                          ),
                        ),
                    ],
                  ),
                  if (place.address.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      place.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String exploreCategoryLabel(String category, String language) =>
    switch (category) {
      'activities' => language == 'zh' ? '玩乐与风景' : 'Sights & activities',
      'parks' => language == 'zh' ? '公园与绿地' : 'Parks & gardens',
      'food' => language == 'zh' ? '美食' : 'Food',
      'coffee' => language == 'zh' ? '咖啡' : 'Coffee',
      'shopping' => language == 'zh' ? '购物' : 'Shopping',
      _ => category,
    };

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback({required this.category, required this.language});
  final String category, language;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (category) {
      'parks' => Icons.park_rounded,
      'food' => Icons.restaurant_rounded,
      'coffee' => Icons.coffee_rounded,
      'shopping' => Icons.shopping_bag_rounded,
      _ => Icons.landscape_rounded,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.surfaceContainerLow],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Icon(icon, size: 36, color: scheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exploreCategoryLabel(category, language),
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    language == 'zh'
                        ? '跟着 Waybi，去发现'
                        : 'A little find with Waybi',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const WaybiBird(size: 48),
          ],
        ),
      ),
    );
  }
}
