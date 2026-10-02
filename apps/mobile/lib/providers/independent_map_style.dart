import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vector;

/// Calm, readable cartography. Lime belongs to route guidance, not every road.
Map<String, dynamic> kiwiMapStyle(
  Map<String, dynamic> base, {
  required bool dark,
  required String language,
}) {
  final result = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
  // Tile caches include theme identity: keep languages and appearances distinct.
  result['id'] = 'kiwi-${dark ? "night" : "day"}-$language';
  final paper = dark ? '#1e2527' : '#f7f8f4';
  final land = dark ? '#252d2e' : '#f0f2ec';
  final park = dark ? '#28392e' : '#e5eddd';
  final water = dark ? '#233e49' : '#cce2eb';
  final road = dark ? '#465152' : '#ffffff';
  final roadEdge = dark ? '#2a3336' : '#d9ded7';
  for (final layer in (result['layers'] as List).cast<Map<String, dynamic>>()) {
    final id = layer['id'] as String;
    final type = layer['type'];
    final paint = layer.putIfAbsent(
      'paint',
      () => <String, dynamic>{},
    ) as Map<String, dynamic>;
    if (type == 'background') paint['background-color'] = paper;
    if (type == 'fill') {
      paint['fill-color'] = id.contains('water')
          ? water
          : id.contains('park') || id.contains('wood')
          ? park
          : id.contains('building')
          ? (dark ? '#30393a' : '#e9ede6')
          : land;
      if (id == 'building') {
        paint['fill-outline-color'] = dark ? '#394245' : '#e0e5dc';
      }
    }
    if (type == 'line') {
      paint['line-color'] = id.contains('water')
          ? water
          : id.contains('casing') ||
                id.contains('boundary') ||
                id.contains('railway')
          ? roadEdge
          : road;
      if (id == 'highway_minor') {
        paint['line-color'] = dark ? '#3b4648' : '#ffffff';
      }
      if (id.contains('railway')) layer['minzoom'] = 16;
    }
    if (type == 'symbol') {
      paint['text-color'] = id.contains('water')
          ? (dark ? '#8aaebd' : '#668a9b')
          : (dark ? '#d0d8d4' : '#647166');
      paint['text-halo-color'] = paper;
      paint['text-halo-width'] = 1.5;
      final layout = layer['layout'] as Map<String, dynamic>?;
      if (layout != null &&
          layout.containsKey('text-field') &&
          !id.contains('shield')) {
        layout['text-field'] = [
          'coalesce',
          if (language == 'zh') ['get', 'name:zh'],
          ['get', 'name'],
          ['get', 'name:en'],
        ];
        layout['text-font'] = ['Hiragino Sans GB', 'Hiragino Sans', 'Roboto'];
      }
    }
  }
  (result['layers'] as List).removeWhere(
    (dynamic layer) =>
        layer['id'] == 'highway-name-path' ||
        layer['id'].toString().contains('shield-us') ||
        layer['id'] == 'road_shield_us',
  );
  return result;
}

class IndependentMapStyle {
  static Future<Style>? _source;
  static bool _licensesRegistered = false;
  static Future<Style> load({
    required bool dark,
    required String language,
  }) async {
    if (!_licensesRegistered) {
      _licensesRegistered = true;
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks([
          'Kiwi map style / Positron / OpenFreeMap',
        ], await rootBundle.loadString('assets/maps/LICENSES.txt'));
      });
    }
    _source ??=
        StyleReader(
          uri: const String.fromEnvironment(
            'KIWI_VECTOR_STYLE_URL',
            defaultValue: 'https://tiles.openfreemap.org/styles/positron',
          ),
          httpHeaders: {
            if (!kIsWeb)
              'User-Agent':
                  'KiwiLens/1.0 (+https://github.com/yaohuangguan/kiwi-lens)',
          },
        ).read().timeout(const Duration(seconds: 20)).catchError((Object e) {
          _source = null;
          throw e;
        });
    final source = await _source!;
    final base = jsonDecode(
      await rootBundle.loadString('assets/maps/positron_base.json'),
    ) as Map<String, dynamic>;
    return Style(
      name: 'Kiwi Lens',
      theme: vector.ThemeReader().read(
        kiwiMapStyle(base, dark: dark, language: language),
      ),
      providers: source.providers,
      sprites: source.sprites,
    );
  }
}
