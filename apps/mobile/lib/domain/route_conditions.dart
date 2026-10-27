/// Published NZTA congestion levels are ranking evidence, not measured delay.
class RouteConditions {
  const RouteConditions({
    required this.expiresAt,
    required this.trafficStatus,
    this.coveredMeters = 0,
    this.heavyMeters = 0,
    this.moderateMeters = 0,
    this.rankingPenalty = 0,
    this.incidentIds = const [],
    this.roadworkIds = const [],
  });
  final DateTime? expiresAt;
  final String trafficStatus;
  final int coveredMeters, heavyMeters, moderateMeters, rankingPenalty;
  final List<String> incidentIds, roadworkIds;
  bool get current => expiresAt?.isAfter(DateTime.now()) ?? false;
  bool get hasTraffic =>
      current && trafficStatus == 'live' && coveredMeters > 0;
  int get currentPenalty => current ? rankingPenalty : 0;
  factory RouteConditions.fromJson(Map<String, dynamic> json) =>
      RouteConditions(
        expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
        trafficStatus: json['trafficStatus']?.toString() ?? 'unavailable',
        coveredMeters: (json['coveredMeters'] as num?)?.round() ?? 0,
        heavyMeters: (json['heavyMeters'] as num?)?.round() ?? 0,
        moderateMeters: (json['moderateMeters'] as num?)?.round() ?? 0,
        rankingPenalty: ((json['rankingPenalty'] as num?)?.round() ?? 0).clamp(
          0,
          1800,
        ),
        incidentIds: (json['incidentIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        roadworkIds: (json['roadworkIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
      );
  String trafficLabel(bool zh) {
    if (!current || trafficStatus == 'stale') {
      return zh ? '路况已过期' : 'Traffic outdated';
    }
    if (!hasTraffic) return zh ? '路况未覆盖' : 'Traffic not covered';
    if (heavyMeters > 0) return zh ? '部分路段拥堵' : 'Heavy sections';
    if (moderateMeters > 0) return zh ? '部分路段缓行' : 'Slow sections';
    return zh ? '已知路段顺畅' : 'Known sections clear';
  }
}
