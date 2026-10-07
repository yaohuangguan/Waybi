import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/providers/independent_map_style.dart';

void main() {
  final base = jsonDecode(
    File('assets/maps/positron_base.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  test('bundled day/night styles parse with distinct cache identities and retain tile sources', () {
    final day = waybiMapStyle(base, dark: false, language: 'zh');
    final night = waybiMapStyle(base, dark: true, language: 'zh');
    final english = waybiMapStyle(base, dark: false, language: 'en');
    expect(day['id'], isNot(night['id']));
    expect(day['id'], isNot(english['id']));
    final daySource =
        (day['sources'] as Map<String, dynamic>)['openmaptiles']
            as Map<String, dynamic>;
    final baseSource =
        (base['sources'] as Map<String, dynamic>)['openmaptiles']
            as Map<String, dynamic>;
    expect(daySource['url'], baseSource['url']);
    expect(daySource['attribution'], contains('OpenStreetMap'));
    expect(daySource['attribution'], contains('OpenMapTiles'));
    expect(night['layers'], isNot(day['layers']));
    expect(base['id'], isNot(day['id']));
  });
  test(
    'native style supplies POIs, hosted fonts and distinct land/road colours',
    () {
      final style = waybiMapStyle(base, dark: false, language: 'zh');
      final layers = (style['layers'] as List).cast<Map<String, dynamic>>();
      Map<String, dynamic> layer(String id) =>
          layers.singleWhere((l) => l['id'] == id);
      expect(layer('waybi-poi-label')['source-layer'], 'poi');
      expect(layer('waybi-poi-label')['layout']['text-allow-overlap'], false);
      expect(layer('waybi-poi-label')['layout']['text-font'], [
        'Noto Sans Regular',
      ]);
      expect(
        layer('waybi-landuse')['paint']['fill-color'].toString(),
        contains('hospital'),
      );
      expect(
        layer('park')['paint']['fill-color'],
        isNot(layer('water')['paint']['fill-color']),
      );
      expect(layer('highway_motorway_inner')['paint']['line-color'], '#e1e4e7');
      expect(
        layer('highway_motorway_casing')['paint']['line-color'],
        '#c9cdd1',
      );
      expect(
        layer('highway_motorway_inner')['paint']['line-color'],
        isNot(layer('highway_minor')['paint']['line-color']),
      );
      expect(
        layer('highway_major_inner')['paint']['line-color'],
        isNot(layer('highway_minor')['paint']['line-color']),
      );
    },
  );
  test(
    'road overlays stay below street names, motorway shields and place labels',
    () {
      for (final dark in [false, true]) {
        final layers =
            (waybiMapStyle(base, dark: dark, language: 'zh')['layers'] as List)
                .cast<Map<String, dynamic>>();
        final anchor = layers.indexWhere((l) => l['id'] == 'waybi-poi-dot');
        expect(
          anchor,
          greaterThan(
            layers.indexWhere(
              (l) => l['id'] == 'highway_motorway_bridge_inner',
            ),
          ),
        );
        for (final label in layers.where((l) => l['type'] == 'symbol')) {
          expect(
            layers.indexOf(label),
            greaterThan(anchor),
            reason: label['id'] as String,
          );
        }
      }
    },
  );
  test('local language changes preserve highway reference shields', () {
    final custom = <String, dynamic>{
      'layers': [
        {
          'id': 'road-name',
          'type': 'symbol',
          'layout': {'text-field': '{name:latin}'},
          'paint': <String, dynamic>{},
        },
        {
          'id': 'highway-shield',
          'type': 'symbol',
          'layout': {'text-field': '{ref}'},
          'paint': <String, dynamic>{},
        },
      ],
    };
    final styled = waybiMapStyle(custom, dark: false, language: 'zh');
    final layers = styled['layers'] as List;
    expect(
      layers
          .singleWhere((l) => l['id'] == 'road-name')['layout']['text-field']
          .toString(),
      contains('name:zh'),
    );
    expect(
      layers.singleWhere(
        (l) => l['id'] == 'highway-shield',
      )['layout']['text-field'],
      '{ref}',
    );
    expect(custom['layers'][0]['layout']['text-field'], '{name:latin}');
  });

  test(
    'Waybi-hosted map endpoints can replace every runtime basemap asset',
    () {
      final styled = waybiMapStyle(
        base,
        dark: false,
        language: 'en',
        vectorSource: 'pmtiles://https://maps.waybi.co/nz.pmtiles',
        naturalEarthTemplate:
            'https://maps.waybi.co/natural-earth/{z}/{x}/{y}.png',
        spriteUrl: 'https://maps.waybi.co/sprites/waybi',
        glyphsUrl: 'https://maps.waybi.co/fonts/{fontstack}/{range}.pbf',
      );
      final sources = styled['sources'] as Map<String, dynamic>;
      expect(
        (sources['openmaptiles'] as Map<String, dynamic>)['url'],
        'pmtiles://https://maps.waybi.co/nz.pmtiles',
      );
      expect((sources['ne2_shaded'] as Map<String, dynamic>)['tiles'], [
        'https://maps.waybi.co/natural-earth/{z}/{x}/{y}.png',
      ]);
      expect(styled['sprite'], 'https://maps.waybi.co/sprites/waybi');
      expect(
        styled['glyphs'],
        'https://maps.waybi.co/fonts/{fontstack}/{range}.pbf',
      );
    },
  );
}
