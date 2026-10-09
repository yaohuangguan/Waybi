import 'dart:convert';

import 'package:flutter/services.dart';

import 'map_provider.dart';

/// Map-only, council-street-centreline corridors. These are NOT lane geometry
/// or evidence that an entire road is restricted, and must never be passed to
/// the route matcher, camera matcher or road-access filter.
class TransitReviewCorridor {
  const TransitReviewCorridor({
    required this.id,
    required this.city,
    required this.roadName,
    required this.authority,
    required this.ruleSummary,
    required this.ruleSummaryZh,
    required this.ruleSource,
    required this.geometrySource,
    required this.points,
  });

  final String id,
      city,
      roadName,
      authority,
      ruleSummary,
      ruleSummaryZh,
      ruleSource,
      geometrySource;
  final List<GeoPoint> points;

  factory TransitReviewCorridor.fromJson(Map<String, dynamic> json) {
    if (json['precision'] != 'corridor-only') {
      throw const FormatException(
        'Transit review corridor must be approximate',
      );
    }
    final source = Uri.tryParse(json['ruleSource'] as String? ?? '');
    if (source == null || source.scheme != 'https' || source.host.isEmpty) {
      throw const FormatException(
        'Transit review corridor source must use HTTPS',
      );
    }
    final coordinates = (json['coordinates'] as List).cast<List>();
    final points = coordinates
        .where((value) => value.length >= 2)
        .map(
          (value) => GeoPoint(
            (value[1] as num).toDouble(),
            (value[0] as num).toDouble(),
          ),
        )
        .toList(growable: false);
    if (points.length < 2) {
      throw const FormatException('Invalid street centreline');
    }
    return TransitReviewCorridor(
      id: json['id'] as String,
      city: json['city'] as String,
      roadName: json['roadName'] as String,
      authority: json['authority'] as String,
      ruleSummary: json['ruleSummary'] as String,
      ruleSummaryZh: json['ruleSummaryZh'] as String,
      ruleSource: json['ruleSource'] as String,
      geometrySource: json['geometrySource'] as String,
      points: points,
    );
  }
}

Future<List<TransitReviewCorridor>> loadBundledTransitReviewCorridors() async {
  final data = jsonDecode(
    await rootBundle.loadString('assets/data/transit-corridors-review.json'),
  ) as Map<String, dynamic>;
  if (data['schemaVersion'] != 1 ||
      data['datasetType'] !=
          'map-review-corridors-not-navigation-restrictions') {
    throw const FormatException('Unexpected transit review data');
  }
  final rows = (data['corridors'] as List)
      .cast<Map<String, dynamic>>()
      .map(TransitReviewCorridor.fromJson)
      .toList(growable: false);
  if (rows.isEmpty) {
    throw const FormatException('Empty transit corridor review dataset');
  }
  return rows;
}
