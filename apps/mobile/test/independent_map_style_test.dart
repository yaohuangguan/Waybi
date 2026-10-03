import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_lens_mobile/providers/independent_map_style.dart';

void main() {
  final base = jsonDecode(
    File('assets/maps/positron_base.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  test('bundled day/night styles parse with distinct cache identities and retain tile sources', () {
    final day = kiwiMapStyle(base, dark: false, language: 'zh');
    final night = kiwiMapStyle(base, dark: true, language: 'zh');
    final english = kiwiMapStyle(base, dark: false, language: 'en');
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
      final style = kiwiMapStyle(base, dark: false, language: 'zh');
      final layers = (style['layers'] as List).cast<Map<String, dynamic>>();
      Map<String, dynamic> layer(String id) =>
          layers.singleWhere((l) => l['id'] == id);
      expect(layer('kiwi-poi-label')['source-layer'], 'poi');
      expect(layer('kiwi-poi-label')['layout']['text-allow-overlap'], false);
      expect(layer('kiwi-poi-label')['layout']['text-font'], [
        'Noto Sans Regular',
      ]);
      expect(
        layer('kiwi-landuse')['paint']['fill-color'].toString(),
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
    final styled = kiwiMapStyle(custom, dark: false, language: 'zh');
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
}
