import 'package:flutter/material.dart';

import '../domain/china_region.dart';
import '../theme/waybi_theme.dart';

/// A clear caution that the matched place is far away, shown instead of
/// silently routing hundreds of kilometres to a namesake.
class FarMatchNotice extends StatelessWidget {
  const FarMatchNotice({
    super.key,
    required this.title,
    required this.detail,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 4),
  });

  final String title;
  final String detail;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final status = context.status;
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $detail',
      child: ExcludeSemantics(
        child: Container(
          key: const Key('farMatchNotice'),
          margin: margin,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: status.warningContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: status.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: status.onWarningContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      detail,
                      style: TextStyle(
                        color: status.onWarningContainer,
                        fontSize: WaybiTextSize.caption,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The attribution Amap requires next to its places, routes and traffic.
class AmapAttributionLabel extends StatelessWidget {
  const AmapAttributionLabel({
    super.key,
    required this.language,
    this.routes = false,
    this.padding = const EdgeInsets.fromLTRB(18, 6, 18, 6),
  });

  final String language;
  final bool routes;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final zh = language == 'zh';
    final label = routes
        ? (zh ? '路线与路况：$amapAttribution' : 'Route & traffic: $amapAttribution')
        : (zh ? '地点数据：$amapAttribution' : 'Places: $amapAttribution');
    return Padding(
      padding: padding,
      child: Text(
        label,
        key: const Key('amapAttribution'),
        style: TextStyle(
          color: context.colors.onSurfaceVariant,
          fontSize: WaybiTextSize.caption,
        ),
      ),
    );
  }
}
