import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/theme/waybi_theme.dart';
import 'package:waybi_mobile/widgets/splash_gate.dart';
import 'package:waybi_mobile/widgets/waybi_bird.dart';

String resource(String path) => File(path).readAsStringSync();

String style(String contents, String name) =>
    RegExp('<style name="$name"[^>]*>([\\s\\S]*?)</style>')
        .firstMatch(contents)!
        .group(1)!;

Color hexColor(String rgb) => Color(0xff000000 | int.parse(rgb, radix: 16));

/// The asset-catalog colour for [appearance] (`null`: the default, light).
Color colorSetColor(Map<String, dynamic> set, String? appearance) {
  final entry = (set['colors'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((entry) {
        final appearances = (entry['appearances'] as List?) ?? const [];
        return appearance == null
            ? appearances.isEmpty
            : appearances.any(
                (a) =>
                    a['appearance'] == 'luminosity' && a['value'] == appearance,
              );
      });
  final color = entry['color'] as Map<String, dynamic>;
  expect(color['color-space'], 'srgb');
  final components = color['components'] as Map<String, dynamic>;
  int channel(String name) =>
      int.parse((components[name] as String).replaceFirst('0x', ''), radix: 16);
  expect(double.parse(components['alpha'] as String), 1);
  return Color.fromARGB(255, channel('red'), channel('green'), channel('blue'));
}

void main() {
  test('the launch screens and SplashGate share one light and one dark '
      'colour', () {
    expect(SplashGate.lightBackground, WaybiColors.lightBackground);
    expect(SplashGate.darkBackground, WaybiColors.midnightOcean);
    expect(SplashGate.darkBackground, isNot(SplashGate.lightBackground));
  });

  test('iOS engine startup matches Flutter in light and dark mode without a '
      'separate branded screen', () {
    final plist = resource('ios/Runner/Info.plist');
    expect(plist, contains('<string>LaunchScreen</string>'));
    final storyboard = resource(
      'ios/Runner/Base.lproj/LaunchScreen.storyboard',
    );
    expect(storyboard, contains('launchScreen="YES"'));
    expect(RegExp(r'<(?:imageView|label)\b').hasMatch(storyboard), isFalse);
    // The background is the LaunchBackground colour set, which has a Dark
    // appearance; a fixed colour would flash light in dark mode.
    expect(
      RegExp(r'<color key="backgroundColor"[^>]+>')
          .firstMatch(storyboard)!
          .group(0),
      '<color key="backgroundColor" name="LaunchBackground"/>',
    );
    expect(storyboard, contains('<capability name="Named colors"'));
    final fallback = RegExp(
      r'<namedColor name="LaunchBackground">\s*<color ([^>]+)/>',
    ).firstMatch(storyboard)!.group(1)!;
    final expected = SplashGate.lightBackground;
    for (final channel in {
      'red': expected.r,
      'green': expected.g,
      'blue': expected.b,
      'alpha': expected.a,
    }.entries) {
      final nativeValue = double.parse(
        RegExp('${channel.key}="([^"]+)"').firstMatch(fallback)!.group(1)!,
      );
      expect(nativeValue, closeTo(channel.value, 1e-9), reason: channel.key);
    }
    final set = jsonDecode(
      resource(
        'ios/Runner/Assets.xcassets/LaunchBackground.colorset/Contents.json',
      ),
    ) as Map<String, dynamic>;
    expect(colorSetColor(set, null), SplashGate.lightBackground);
    expect(colorSetColor(set, 'dark'), SplashGate.darkBackground);
  });

  test('Android startup matches Flutter in light and night mode across API '
      'variants', () {
    const res = 'android/app/src/main/res';
    Color launchColor(String folder) => hexColor(
      RegExp(r'<color name="waybi_launch_background">#([0-9a-fA-F]{6})</color>')
          .firstMatch(resource('$res/$folder/colors.xml'))!
          .group(1)!,
    );
    expect(launchColor('values'), SplashGate.lightBackground);
    expect(launchColor('values-night'), SplashGate.darkBackground);
    // Every launch resource uses the one colour name, which the night
    // qualifier resolves to the dark variant.
    final drawables = Directory(res)
        .listSync()
        .whereType<Directory>()
        .map((folder) => File('${folder.path}/launch_background.xml'))
        .where((file) => file.existsSync())
        .toList();
    expect(drawables, hasLength(greaterThanOrEqualTo(2)));
    for (final file in drawables) {
      final background = file.readAsStringSync();
      expect(
        background,
        contains('android:drawable="@color/waybi_launch_background"'),
        reason: file.path,
      );
      expect(RegExp(r'<(?:bitmap|vector)\b').hasMatch(background), isFalse);
    }
    for (final (folder, parent) in [
      ('values', 'Theme.Light.NoTitleBar'),
      ('values-night', 'Theme.Black.NoTitleBar'),
    ]) {
      final styles = resource('$res/$folder/styles.xml');
      expect(
        style(styles, 'LaunchTheme'),
        contains('@drawable/launch_background'),
      );
      expect(
        style(styles, 'NormalTheme'),
        contains('@color/waybi_launch_background'),
      );
      expect(
        styles,
        contains('<style name="LaunchTheme" parent="@android:style/$parent">'),
      );
    }
    // Android 12 otherwise substitutes the launcher icon even when the legacy
    // background has no logo. Night-v31 must not fall back to that behavior.
    for (final (folder, parent) in [
      ('values-v31', 'Theme.Light.NoTitleBar'),
      ('values-night-v31', 'Theme.Black.NoTitleBar'),
    ]) {
      final styles = resource('$res/$folder/styles.xml');
      final launch = style(styles, 'LaunchTheme');
      expect(
        launch,
        contains(
          '<item name="android:windowSplashScreenBackground">@color/waybi_launch_background</item>',
        ),
      );
      expect(
        launch,
        contains(
          '<item name="android:windowSplashScreenAnimatedIcon">@drawable/launch_empty</item>',
        ),
      );
      expect(launch, isNot(contains('@mipmap/ic_launcher')));
      expect(
        styles,
        contains('<style name="LaunchTheme" parent="@android:style/$parent">'),
      );
    }
    final icon = resource('$res/drawable/launch_empty.xml');
    expect(icon, contains('android:fillColor="#00000000"'));
    expect(RegExp(r'<path\b').allMatches(icon), hasLength(1));
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final system in Brightness.values) {
      testWidgets(
        'one branded splash hands off once on $platform / system $system',
        (t) async {
          t.platformDispatcher.platformBrightnessTestValue = system;
          addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
          // The app's own theme is the opposite: the splash still follows the
          // system, like the native launch screen before it.
          Widget app(Brightness theme) => MaterialApp(
            theme: ThemeData(platform: platform, brightness: theme),
            home: const SplashGate(child: Scaffold(body: Text('Map ready'))),
          );
          final opposite = system == Brightness.light
              ? Brightness.dark
              : Brightness.light;
          await t.pumpWidget(app(opposite));
          final splash = find.byKey(const ValueKey('waybi-splash'));
          expect(
            t.widget<Scaffold>(splash).backgroundColor,
            system == Brightness.dark
                ? SplashGate.darkBackground
                : SplashGate.lightBackground,
          );
          final title = t.widget<Text>(find.text('Waybi'));
          expect(
            title.style!.color,
            system == Brightness.dark
                ? WaybiColors.darkText
                : WaybiColors.deepOcean,
          );
          expect(find.byType(WaybiBird), findsOneWidget);
          expect(find.text('Meet Waybi. Find your way.'), findsOneWidget);
          expect(find.text('Map ready'), findsNothing);
          await t.pump(const Duration(milliseconds: 1051));
          await t.pumpAndSettle();
          expect(splash, findsNothing);
          expect(find.byType(WaybiBird), findsNothing);
          expect(find.text('Map ready'), findsOneWidget);
          // Switching the system appearance later never brings it back.
          t.platformDispatcher.platformBrightnessTestValue = opposite;
          await t.pumpWidget(app(system));
          await t.pumpAndSettle();
          expect(splash, findsNothing);
          expect(find.text('Map ready'), findsOneWidget);
        },
      );
    }
  }
}
