import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/place_details_repository.dart';
import '../domain/coordinate_formatter.dart';
import '../domain/map_provider.dart';
import '../domain/route_option.dart';
import '../theme/waybi_theme.dart';
import 'waybi_bird.dart';

class PlaceDetailsContent extends StatefulWidget {
  const PlaceDetailsContent({
    super.key,
    required this.selectedPlace,
    required this.details,
    required this.detailsLoading,
    required this.detailsError,
    required this.routeBusy,
    this.quickRoute,
    this.quickRouteLoading = false,
    this.navigationAvailable = true,
    required this.isFavorite,
    required this.onClose,
    required this.onNavigate,
    required this.onFavorite,
    required this.onReview,
    this.language = 'en',
    this.onExpandedChanged,
  });

  final PlaceSummary selectedPlace;
  final PlaceDetails? details;
  final bool detailsLoading;
  final String? detailsError;
  final bool routeBusy;
  final RouteOption? quickRoute;
  final bool quickRouteLoading;
  final bool navigationAvailable;
  final bool isFavorite;
  final VoidCallback onClose;
  final VoidCallback onNavigate;
  final VoidCallback onFavorite;
  final VoidCallback onReview;
  final String language;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  State<PlaceDetailsContent> createState() => _PlaceDetailsContentState();
}

class _PlaceDetailsContentState extends State<PlaceDetailsContent> {
  bool _expanded = false;
  double _dragDelta = 0;

  String _text(String en, String zh) => widget.language == 'zh' ? zh : en;

  bool _samePlace(PlaceSummary a, PlaceSummary b) {
    final aRef = a.reference;
    final bRef = b.reference;
    if (aRef != null && bRef != null) {
      return aRef.provider == bRef.provider && aRef.id == bRef.id;
    }
    return a.name == b.name && a.location == b.location;
  }

  @override
  void didUpdateWidget(covariant PlaceDetailsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_samePlace(oldWidget.selectedPlace, widget.selectedPlace)) {
      _expanded = false;
      _dragDelta = 0;
    }
  }

  void _setExpanded(bool value) {
    if (_expanded == value) return;
    setState(() => _expanded = value);
    widget.onExpandedChanged?.call(value);
  }

  void _toggleExpanded() => _setExpanded(!_expanded);

  String _durationLabel(int seconds) {
    final minutes = (seconds / 60).ceil().clamp(1, 9999);
    if (minutes < 60) return _text('$minutes min', '$minutes 分钟');
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (remainder == 0) return _text('${hours}h', '$hours 小时');
    return _text('${hours}h ${remainder}m', '$hours 小时 $remainder 分');
  }

  String _distanceLabel(int meters) {
    if (meters < 1000) return _text('$meters m', '$meters 米');
    final km = meters / 1000;
    return _text(
      '${km.toStringAsFixed(km < 10 ? 1 : 0)} km',
      '${km.toStringAsFixed(km < 10 ? 1 : 0)} 公里',
    );
  }

  Widget _quickRouteSummary(ColorScheme scheme) {
    if (!widget.navigationAvailable) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
        child: Row(
          children: [
            Icon(Icons.public_rounded, size: 16, color: scheme.primary),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                _text(
                  'Worldwide place found · turn-by-turn navigation is currently NZ-only',
                  '已找到全球地点 · 逐向导航目前仅支持新西兰',
                ),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final route = widget.quickRoute;
    if (route == null && !widget.quickRouteLoading) {
      return const SizedBox.shrink();
    }
    if (route == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _text('Checking drive time…', '正在获取驾车时间…'),
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final delaySeconds = route.trafficDelaySeconds ?? 0;
    final delayMinutes = (delaySeconds / 60).round();
    final trafficHeavy = delaySeconds >= 300 || route.traffic.trafficJam > 0;
    final trafficModerate = delaySeconds >= 120 || route.traffic.slow > 0;
    final trafficColor = trafficHeavy
        ? WaybiColors.danger
        : trafficModerate
        ? WaybiColors.warning
        : WaybiColors.success;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: .58),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: .55),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.directions_car_filled_rounded,
              size: 18,
              color: scheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              _durationLabel(route.durationSeconds),
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              '· ${_distanceLabel(route.distanceMeters)}',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: trafficColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              delayMinutes >= 2
                  ? _text('+$delayMinutes min traffic', '拥堵 +$delayMinutes 分钟')
                  : _text('Traffic good', '路况良好'),
              style: TextStyle(
                color: trafficColor,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _settleDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final movement = _dragDelta.abs() >= 18 ? _dragDelta : velocity / 12;
    _dragDelta = 0;
    if (movement.abs() < 18) return;
    _setExpanded(movement < 0);
  }

  Widget _compactThumbnail(
    ColorScheme scheme,
    String title,
    PlaceDetails? place,
  ) {
    final photo = place?.photos.isNotEmpty == true ? place!.photos.first : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 88,
        height: 88,
        child: photo == null
            ? ColoredBox(
                color: scheme.primaryContainer,
                child: const Center(child: WaybiBird(size: 60)),
              )
            : Image.network(
                photo.url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: scheme.primaryContainer,
                  child: Icon(
                    Icons.place_rounded,
                    color: scheme.primary,
                    size: 30,
                  ),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selectedPlace = widget.selectedPlace;
    final place = widget.details;
    final address = place?.address.isNotEmpty == true
        ? place!.address
        : selectedPlace.address.isNotEmpty
        ? selectedPlace.address
        : formatCoordinate(
            selectedPlace.location.latitude,
            selectedPlace.location.longitude,
          );
    final title = selectedPlace.reference?.provider == 'google'
        ? place?.name ?? selectedPlace.name
        : selectedPlace.name;
    final rawType =
        (place?.primaryType.isNotEmpty == true
                ? place!.primaryType
                : selectedPlace.category)
            .replaceAll('_', ' ')
            .trim();
    final typeNames = <String, (String, String)>{
      'cafe': ('Café', '咖啡馆'),
      'coffee': ('Café', '咖啡馆'),
      'restaurant': ('Restaurant', '餐厅'),
      'food': ('Food & drink', '餐饮'),
      'park': ('Park', '公园'),
      'parks': ('Park & nature', '公园与自然'),
      'garden': ('Garden', '花园'),
      'supermarket': ('Supermarket', '超市'),
      'shopping': ('Shopping', '购物'),
      'shop': ('Shop', '商店'),
      'activities': ('Things to do', '景点与活动'),
      'museum': ('Museum', '博物馆'),
      'attraction': ('Attraction', '景点'),
      'gallery': ('Gallery', '美术馆'),
      'art gallery': ('Art gallery', '美术馆'),
      'hospital': ('Hospital', '医院'),
      'school': ('School', '学校'),
      'hotel': ('Hotel', '酒店'),
      'parking': ('Parking', '停车场'),
      'fuel': ('Petrol station', '加油站'),
      'bakery': ('Bakery', '面包店'),
      'residential': ('Street', '街道'),
      'house': ('Address', '地址'),
    };
    final names = typeNames[rawType];
    final type = names == null
        ? (rawType.isEmpty ? _text('Place', '地点') : rawType)
        : _text(names.$1, names.$2);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = _expanded
        ? (screenHeight * .72).clamp(430.0, 660.0)
        : (screenHeight * .38).clamp(285.0, 340.0);

    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: Material(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: theme.dividerColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  key: const Key('placeDeckHandle'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleExpanded,
                  onVerticalDragStart: (_) => _dragDelta = 0,
                  onVerticalDragUpdate: (details) =>
                      _dragDelta += details.delta.dy,
                  onVerticalDragEnd: _settleDrag,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.dividerColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_expanded && place?.photos.isNotEmpty == true)
                  _PhotoStrip(photos: place!.photos)
                else if (_expanded)
                  _PhotoFallback(title: title),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, _expanded ? 10 : 2, 8, 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_expanded) ...[
                        _compactThumbnail(scheme, title, place),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: _expanded ? 22 : 18,
                                height: 1.05,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (type.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  type,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: scheme.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close_rounded),
                        tooltip: _text('Close', '关闭'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 17,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SelectableText(
                          address,
                          key: const Key('placeFullAddress'),
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (place?.rating != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: WaybiColors.warning,
                              size: 17,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              place!.rating!.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _text(
                                '${place.userRatingCount ?? 0} ratings',
                                '${place.userRatingCount ?? 0} 条评价',
                              ),
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        if (place.businessStatus != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: scheme.outline,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                place.businessStatus == 'OPERATIONAL'
                                    ? _text('Open / operational', '营业中')
                                    : place.businessStatus!.replaceAll(
                                        '_',
                                        ' ',
                                      ),
                                style: TextStyle(
                                  color: place.businessStatus == 'OPERATIONAL'
                                      ? WaybiColors.success
                                      : scheme.onSurfaceVariant,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                _quickRouteSummary(scheme),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _PlaceAction(
                          icon: Icons.directions_car_filled_rounded,
                          label: !widget.navigationAvailable
                              ? _text('NZ only', '仅新西兰')
                              : widget.routeBusy
                              ? _text('Routing', '规划中')
                              : _text('Drive', '导航'),
                          selected: widget.navigationAvailable,
                          busy: widget.navigationAvailable && widget.routeBusy,
                          onTap: !widget.navigationAvailable || widget.routeBusy
                              ? null
                              : widget.onNavigate,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: _PlaceAction(
                          icon: widget.isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          label: widget.isFavorite
                              ? _text('Saved', '已收藏')
                              : _text('Save', '收藏'),
                          selected: false,
                          onTap: widget.onFavorite,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: _PlaceAction(
                          icon: Icons.ios_share_rounded,
                          label: _text('Share', '分享'),
                          selected: false,
                          onTap: () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text:
                                    '${selectedPlace.name}\n$address\n'
                                    '${selectedPlace.location.latitude},'
                                    '${selectedPlace.location.longitude}',
                              ),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _text(
                                      'Place copied to clipboard',
                                      '地点信息已复制',
                                    ),
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: _PlaceAction(
                          icon: Icons.more_horiz_rounded,
                          label: _text('More', '更多'),
                          selected: false,
                          onTap: widget.onReview,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.detailsLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (widget.detailsError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                    child: Text(
                      widget.detailsError!,
                      style: TextStyle(
                        color: scheme.error,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (!_expanded && place != null)
                  InkWell(
                    onTap: _toggleExpanded,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.keyboard_arrow_up_rounded,
                            size: 17,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _text('Swipe up for details', '上拉查看更多'),
                            style: TextStyle(
                              color: scheme.primary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_expanded && place != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
                    child: _DetailsBody(
                      place: place,
                      language: widget.language,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaceAction extends StatelessWidget {
  const _PlaceAction({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected ? scheme.primary : scheme.surfaceContainerLow;
    final foreground = selected ? scheme.onPrimary : scheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(15),
          border: selected
              ? null
              : Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            else
              Icon(icon, color: foreground, size: 21),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: foreground,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.photos});
  final List<PlacePhoto> photos;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 150,
      child: PageView.builder(
        itemCount: photos.length.clamp(1, 4),
        itemBuilder: (context, index) {
          final photo = photos[index];
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                photo.url,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: scheme.primary,
                          ),
                        ),
                      ),
                errorBuilder: (_, _, _) => ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: .28),
                    ],
                  ),
                ),
              ),
              if (photo.attribution.isNotEmpty)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 6,
                  child: InkWell(
                    onTap: photo.sourceUrl.isEmpty && photo.licenseUrl.isEmpty
                        ? null
                        : () {
                            final uri = Uri.tryParse(
                              photo.sourceUrl.isEmpty
                                  ? photo.licenseUrl
                                  : photo.sourceUrl,
                            );
                            if (uri?.scheme == 'https') {
                              launchUrl(
                                uri!,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                    child: Text(
                      '© ${photo.attribution}',
                      maxLines: 2,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        shadows: [Shadow(blurRadius: 5, color: Colors.black87)],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 92,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.surfaceContainerHighest],
        ),
      ),
      alignment: Alignment.center,
      child: const WaybiBird(size: 64),
    );
  }
}

class _DetailsBody extends StatelessWidget {
  const _DetailsBody({required this.place, required this.language});
  final PlaceDetails place;
  final String language;

  String _text(String en, String zh) => language == 'zh' ? zh : en;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chips = <String>[
      if (place.priceLevel != null) place.priceLevel!.replaceAll('_', ' '),
      if (place.phone.isNotEmpty) place.phone,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chips.isNotEmpty)
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final chip in chips)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Text(
                    chip,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        if (place.editorialSummary.isNotEmpty) ...[
          if (chips.isNotEmpty) const SizedBox(height: 12),
          Text(
            place.editorialSummary,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: scheme.onSurface,
            ),
          ),
        ],
        if (place.openingHours.isNotEmpty) ...[
          const SizedBox(height: 10),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            dense: true,
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(
              _text('Opening hours', '营业时间'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            children: [
              for (final line in place.openingHours)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      line,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (place.reviews.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                _text('Google reviews', 'Google 评价'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                _text(
                  '${place.reviews.length} shown',
                  '显示 ${place.reviews.length} 条',
                ),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 3),
          for (final review in place.reviews) _ReviewTile(review: review),
        ],
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});
  final PlaceReview review;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: scheme.surfaceContainerHighest,
            backgroundImage: review.authorPhoto?.isNotEmpty == true
                ? NetworkImage(review.authorPhoto!)
                : null,
            child: review.authorPhoto?.isNotEmpty == true
                ? null
                : Icon(
                    Icons.person_rounded,
                    size: 17,
                    color: scheme.onSurfaceVariant,
                  ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        review.author,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (review.rating != null)
                      Text(
                        '${review.rating!.toStringAsFixed(1)} ★',
                        style: const TextStyle(
                          color: WaybiColors.warning,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                if (review.relativeTime.isNotEmpty)
                  Text(
                    review.relativeTime,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 9,
                    ),
                  ),
                if (review.text.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    review.text,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
