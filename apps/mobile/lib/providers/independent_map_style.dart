import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native MapLibre style. Land use, road hierarchy and POIs remain distinct.
Map<String, dynamic> waybiMapStyle(
  Map<String, dynamic> base, {
  required bool dark,
  required String language,
}) {
  final result = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
  result['id'] = 'waybi-${dark ? "night" : "day"}-$language';
  final sources = result['sources'] as Map<String, dynamic>?;
  final openMapTiles = sources?['openmaptiles'] as Map<String, dynamic>?;
  if (openMapTiles != null) {
    // Keep attribution in the native MapLibre info control instead of a large
    // custom badge that floats over navigation content.
    openMapTiles['attribution'] =
        '© OpenStreetMap contributors · © OpenMapTiles · Routing: OSRM';
  }
  final paper = dark ? '#192329' : '#f6f7f8';
  final park = dark ? '#294333' : '#cfe6bf';
  final water = dark ? '#204557' : '#e5eef3';
  final text = dark ? '#d9e4e8' : '#59636b';
  final names = <dynamic>[
    'coalesce',
    if (language == 'zh') ['get', 'name:zh'],
    ['get', 'name'],
    ['get', 'name:en'],
    ['get', 'name:latin'],
  ];
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
          ? (dark ? '#334148' : '#e9ebed')
          : id.contains('ice') || id.contains('glacier')
          ? (dark ? '#45555e' : '#f0f3f5')
          : (dark ? '#222e34' : '#f1f2f3');
      if (id == 'building') {
        paint['fill-outline-color'] = dark ? '#405059' : '#dde0e3';
      }
    }
    if (type == 'line') {
      final casing = id.contains('casing');
      final motorway = id.contains('motorway');
      final major = id.contains('major');
      paint['line-color'] = id.contains('water')
          ? water
          : id.contains('boundary') || id.contains('railway')
          ? (dark ? '#53626a' : '#c8cdd1')
          : motorway
          ? (casing
                ? (dark ? '#424b52' : '#c9cdd1')
                : (dark ? '#65717a' : '#e1e4e7'))
          : major
          ? (casing
                ? (dark ? '#59656c' : '#d8dce0')
                : (dark ? '#6f7c84' : '#f7f8f9'))
          : casing
          ? (dark ? '#34444d' : '#e1e4e7')
          : (dark ? '#4d606a' : '#ffffff');
    }
    if (type == 'symbol') {
      paint['text-color'] = id.contains('water')
          ? (dark ? '#91bdd3' : '#437d9e')
          : text;
      paint['text-halo-color'] = paper;
      paint['text-halo-width'] = 1.2;
      final layout = layer['layout'] as Map<String, dynamic>?;
      if (layout != null &&
          layout.containsKey('text-field') &&
          !id.contains('shield')) {
        layout['text-field'] = names;
        // These glyphs are served by OpenFreeMap; system iOS fonts are not.
        layout['text-font'] = ['Noto Sans Regular'];
      }
    }
  }
  final layers = result['layers'] as List;
  final landIndex = layers.indexWhere(
    (dynamic l) => l['id'] == 'landuse_residential',
  );
  layers.insert(landIndex < 0 ? 1 : landIndex + 1, {
    'id': 'waybi-landuse',
    'type': 'fill',
    'source': 'openmaptiles',
    'source-layer': 'landuse',
    'minzoom': 9,
    'paint': {
      'fill-color': [
        'match',
        ['get', 'class'],
        ['commercial', 'retail'],
        dark ? '#473b30' : '#f1f2f3',
        ['hospital'],
        dark ? '#4a333d' : '#f3f0f1',
        ['school', 'university', 'college'],
        dark ? '#39344b' : '#f2f1f4',
        ['industrial'],
        dark ? '#383e46' : '#eceef0',
        [
          'cemetery',
          'recreation_ground',
          'allotments',
          'grass',
          'meadow',
          'village_green',
        ],
        park,
        dark ? '#222e34' : '#efefe8',
      ],
    },
  });
  // Grassland is a separate tile class, not only parks and woodland.
  final firstWater = layers.indexWhere((dynamic l) => l['id'] == 'water');
  layers.insert(firstWater < 0 ? 1 : firstWater, {
    'id': 'waybi-grass',
    'type': 'fill',
    'source': 'openmaptiles',
    'source-layer': 'landcover',
    'filter': [
      '==',
      ['get', 'class'],
      'grass',
    ],
    'paint': {'fill-color': dark ? '#2d4634' : '#d9edc9', 'fill-opacity': 1},
  });
  final poiColor = <dynamic>[
    'match',
    ['get', 'class'],
    ['food', 'shop', 'grocery'],
    dark ? '#efbd7c' : '#a46b2c',
    ['hospital', 'doctor', 'pharmacy'],
    dark ? '#eea3b6' : '#b25878',
    ['college', 'school', 'library'],
    dark ? '#c3b4ec' : '#7961a6',
    ['park', 'cemetery', 'sports'],
    dark ? '#a4cd91' : '#517f40',
    ['bus', 'railway', 'airport', 'ferry_terminal'],
    dark ? '#92c2e6' : '#437ea9',
    dark ? '#aebecd' : '#617487',
  ];
  final filter = <dynamic>[
    'all',
    ['has', 'name'],
    [
      '<=',
      [
        'coalesce',
        ['get', 'rank'],
        1,
      ],
      [
        'step',
        ['zoom'],
        4,
        14,
        10,
        15,
        25,
        16,
        100,
      ],
    ],
  ];
  // POIs come from the tiles themselves; no per-frame geocoding or widgets.
  // The renderer inserts routes and traffic below this anchor. Keep every
  // base road shield, street name and place label above those road overlays.
  final firstLabel = layers.indexWhere((dynamic l) => l['type'] == 'symbol');
  layers.insert(firstLabel < 0 ? layers.length : firstLabel, {
    'id': 'waybi-poi-dot',
    'type': 'circle',
    'source': 'openmaptiles',
    'source-layer': 'poi',
    'minzoom': 13,
    'filter': filter,
    'paint': {
      'circle-radius': 3.5,
      'circle-color': poiColor,
      'circle-stroke-color': paper,
      'circle-stroke-width': 1.5,
    },
  });
  layers.add({
    'id': 'waybi-poi-label',
    'type': 'symbol',
    'source': 'openmaptiles',
    'source-layer': 'poi',
    'minzoom': 13,
    'filter': filter,
    'layout': {
      'text-field': names,
      'text-font': ['Noto Sans Regular'],
      'text-size': [
        'interpolate',
        ['linear'],
        ['zoom'],
        13,
        11,
        17,
        13,
      ],
      'text-anchor': 'top',
      'text-offset': [0, .6],
      'text-max-width': 9,
      'text-padding': 3,
      'text-allow-overlap': false,
      'symbol-sort-key': [
        'coalesce',
        ['get', 'rank'],
        1,
      ],
    },
    'paint': {
      'text-color': poiColor,
      'text-halo-color': paper,
      'text-halo-width': 1.5,
    },
  });
  return result;
}

class IndependentMapStyle {
  static Future<Map<String, dynamic>>? _base;
  static bool _licensesRegistered = false;
  static Future<String> load({
    required bool dark,
    required String language,
  }) async {
    if (!_licensesRegistered) {
      _licensesRegistered = true;
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks([
          'Waybi map style / Positron / OpenFreeMap',
        ], await rootBundle.loadString('assets/maps/LICENSES.txt'));
      });
    }
    // Load once from the bundle. Native MapLibre fetches/decodes/caches tiles.
    _base ??= rootBundle
        .loadString('assets/maps/positron_base.json')
        .then((s) => jsonDecode(s) as Map<String, dynamic>);
    return jsonEncode(
      waybiMapStyle(await _base!, dark: dark, language: language),
    );
  }
}
