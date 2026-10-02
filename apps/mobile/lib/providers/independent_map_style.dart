import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native MapLibre style. Land use, road hierarchy and POIs remain distinct.
Map<String, dynamic> kiwiMapStyle(
  Map<String, dynamic> base, {
  required bool dark,
  required String language,
}) {
  final result = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
  result['id'] = 'kiwi-${dark ? "night" : "day"}-$language';
  final paper = dark ? '#192329' : '#f7f7f2';
  final park = dark ? '#294333' : '#cfe8c1';
  final water = dark ? '#204557' : '#add5ed';
  final text = dark ? '#d9e4e8' : '#40505e';
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
          ? (dark ? '#334148' : '#e3e0d8')
          : id.contains('ice') || id.contains('glacier')
          ? (dark ? '#45555e' : '#e9f1f5')
          : (dark ? '#222e34' : '#efefe8');
      if (id == 'building') {
        paint['fill-outline-color'] = dark ? '#405059' : '#d1cdc3';
      }
    }
    if (type == 'line') {
      final casing = id.contains('casing');
      final motorway = id.contains('motorway');
      final major = id.contains('major');
      paint['line-color'] = id.contains('water')
          ? water
          : id.contains('boundary') || id.contains('railway')
          ? (dark ? '#53626a' : '#b8c2c4')
          : motorway
          ? (casing
                ? (dark ? '#8b6640' : '#dfb75f')
                : (dark ? '#b88b50' : '#ffd786'))
          : major
          ? (casing
                ? (dark ? '#71633f' : '#dfcf92')
                : (dark ? '#998255' : '#ffedb3'))
          : casing
          ? (dark ? '#34444d' : '#d9d8cf')
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
    'id': 'kiwi-landuse',
    'type': 'fill',
    'source': 'openmaptiles',
    'source-layer': 'landuse',
    'minzoom': 9,
    'paint': {
      'fill-color': [
        'match',
        ['get', 'class'],
        ['commercial', 'retail'],
        dark ? '#473b30' : '#fae8cb',
        ['hospital'],
        dark ? '#4a333d' : '#f5dce4',
        ['school', 'university', 'college'],
        dark ? '#39344b' : '#e9e0f4',
        ['industrial'],
        dark ? '#383e46' : '#e1e5ea',
        ['cemetery', 'recreation_ground', 'allotments'],
        park,
        dark ? '#222e34' : '#efefe8',
      ],
    },
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
  layers.addAll([
    {
      'id': 'kiwi-poi-dot',
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
    },
    {
      'id': 'kiwi-poi-label',
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
    },
  ]);
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
          'Kiwi map style / Positron / OpenFreeMap',
        ], await rootBundle.loadString('assets/maps/LICENSES.txt'));
      });
    }
    // Load once from the bundle. Native MapLibre fetches/decodes/caches tiles.
    _base ??= rootBundle
        .loadString('assets/maps/positron_base.json')
        .then((s) => jsonDecode(s) as Map<String, dynamic>);
    return jsonEncode(
      kiwiMapStyle(await _base!, dark: dark, language: language),
    );
  }
}
