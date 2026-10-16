import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/widgets/place_sources_sheet.dart';

void main() {
  for (final zh in [false, true]) {
    testWidgets(
      'source credits $zh remain scrollable on a small phone and only open valid photo links',
      (t) async {
        t.view.physicalSize = const Size(375, 667);
        t.view.devicePixelRatio = 1;
        addTearDown(() {
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
        });
        final launched = <String>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async {
            if (call.method == 'launch') {
              launched.add((call.arguments as Map)['url'] as String);
              return true;
            }
            return true;
          },
        );
        addTearDown(
          () => messenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/url_launcher'),
            null,
          ),
        );
        Future<void> show(Map<String, dynamic> credit) async {
          await t.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showPlaceSources(
                      context,
                      language: zh ? 'zh' : 'en',
                      providerIds: const [
                        'osm',
                        'here',
                        'tomtom',
                        'geoapify',
                        'regional:auckland-council',
                      ],
                      photoCredit: credit,
                    ),
                    child: const Text('Credits'),
                  ),
                ),
              ),
            ),
          );
          await t.tap(find.text('Credits'));
          await t.pumpAndSettle();
        }

        await show({
          'author': 'Test photographer',
          'license': 'CC BY 4.0',
          'licenseUrl': 'https://creativecommons.org/licenses/by/4.0/',
          'sourceUrl': 'https://commons.wikimedia.org/wiki/File:Test.jpg',
        });
        expect(
          t.takeException(),
          isNull,
          reason: 'Attributions must fit a small phone',
        );
        for (final label in [
          '© OpenStreetMap · ODbL',
          '© OpenMapTiles · CC BY',
          'Powered by Geoapify',
          '© TomTom',
          '© HERE',
          '© Auckland Council Open Data',
          'CC BY 4.0',
          zh ? '查看原图与作者' : 'View original photo & author',
        ]) {
          final target = find.text(label);
          await t.ensureVisible(target);
          await t.pumpAndSettle();
          await t.tap(target);
          await t.pumpAndSettle();
        }
        expect(
          launched,
          containsAll([
            'https://www.openstreetmap.org/copyright',
            'https://www.here.com',
            'https://creativecommons.org/licenses/by/4.0/',
            'https://commons.wikimedia.org/wiki/File:Test.jpg',
          ]),
        );
        Navigator.of(t.element(find.text('Test photographer'))).pop();
        await t.pumpAndSettle();
        await show({
          'license': 'Unsafe licence',
          'licenseUrl': 'http://unsafe.example.test',
          'sourceUrl': 'javascript:alert(1)',
        });
        final before = launched.length;
        for (final label in [
          'Unsafe licence',
          zh ? '查看原图与作者' : 'View original photo & author',
        ]) {
          final target = find.text(label);
          await t.ensureVisible(target);
          await t.pumpAndSettle();
          await t.tap(target);
          await t.pumpAndSettle();
        }
        expect(launched, hasLength(before));
        expect(t.takeException(), isNull);
      },
    );
  }
}
