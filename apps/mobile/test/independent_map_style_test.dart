import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_lens_mobile/providers/independent_map_style.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

void main() {
  final base = jsonDecode(
    File('assets/maps/positron_base.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  test('bundled day/night styles parse with distinct cache identities and retain tile sources', () {
    final day = kiwiMapStyle(base, dark: false, language: 'zh');
    final night = kiwiMapStyle(base, dark: true, language: 'zh');
    final english = kiwiMapStyle(base, dark: false, language: 'en');
    expect(ThemeReader().read(day).id, isNot(ThemeReader().read(night).id));
    expect(ThemeReader().read(day).id, isNot(ThemeReader().read(english).id));
    expect(day['sources'], base['sources']);
    expect(night['layers'], isNot(day['layers']));
    expect(base['id'], isNot(day['id']));
  });
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
      layers.first['layout']['text-field'].toString(),
      contains('name:zh'),
    );
    expect(layers.last['layout']['text-field'], '{ref}');
    expect(custom['layers'][0]['layout']['text-field'], '{name:latin}');
  });
}
