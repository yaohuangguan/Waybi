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

void main() {
  test(
    'iOS engine startup matches Flutter without a separate branded screen',
    () {
      final plist = resource('ios/Runner/Info.plist');
      expect(plist, contains('<string>LaunchScreen</string>'));
      final storyboard = resource(
        'ios/Runner/Base.lproj/LaunchScreen.storyboard',
      );
      expect(storyboard, contains('launchScreen="YES"'));
      expect(RegExp(r'<(?:imageView|label)\b').hasMatch(storyboard), isFalse);
      final background = RegExp(r'<color key="backgroundColor"[^>]+>')
          .firstMatch(storyboard)!
          .group(0)!;
      final expected = WaybiColors.lightBackground;
      for (final channel in {
        'red': expected.r,
        'green': expected.g,
        'blue': expected.b,
        'alpha': expected.a,
      }.entries) {
        final nativeValue = double.parse(
          RegExp('${channel.key}="([^"]+)"').firstMatch(background)!.group(1)!,
        );
        expect(nativeValue, closeTo(channel.value, 1e-9), reason: channel.key);
      }
    },
  );

  test(
    'Android startup stays one color across API and night resource variants',
    () {
      const res = 'android/app/src/main/res';
      final colors = resource('$res/values/colors.xml');
      final rgb = RegExp(
        r'<color name="waybi_launch_background">#([0-9a-fA-F]{6})</color>',
      ).firstMatch(colors)!.group(1)!;
      expect(
        Color(0xff000000 | int.parse(rgb, radix: 16)),
        WaybiColors.lightBackground,
      );
      for (final folder in ['drawable', 'drawable-v21']) {
        final background = resource('$res/$folder/launch_background.xml');
        expect(
          background,
          contains('android:drawable="@color/waybi_launch_background"'),
        );
        expect(RegExp(r'<(?:bitmap|vector)\b').hasMatch(background), isFalse);
      }
      for (final folder in ['values', 'values-night']) {
        final styles = resource('$res/$folder/styles.xml');
        expect(
          style(styles, 'LaunchTheme'),
          contains('@drawable/launch_background'),
        );
        expect(
          style(styles, 'NormalTheme'),
          contains('@color/waybi_launch_background'),
        );
      }
      // Android 12 otherwise substitutes the launcher icon even when the legacy
      // background has no logo. Night-v31 must not fall back to that behavior.
      for (final folder in ['values-v31', 'values-night-v31']) {
        final launch = style(
          resource('$res/$folder/styles.xml'),
          'LaunchTheme',
        );
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
      }
      final icon = resource('$res/drawable/launch_empty.xml');
      expect(icon, contains('android:fillColor="#00000000"'));
      expect(RegExp(r'<path\b').allMatches(icon), hasLength(1));
    },
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'one branded splash hands off once on $platform / $brightness',
        (t) async {
          Widget app(Brightness mode) => MaterialApp(
            theme: ThemeData(platform: platform, brightness: mode),
            home: const SplashGate(child: Scaffold(body: Text('Map ready'))),
          );
          await t.pumpWidget(app(brightness));
          final splash = find.byKey(const ValueKey('waybi-splash'));
          expect(
            t.widget<Scaffold>(splash).backgroundColor,
            WaybiColors.lightBackground,
          );
          expect(find.byType(WaybiBird), findsOneWidget);
          expect(find.text('Waybi'), findsOneWidget);
          expect(find.text('Meet Waybi. Find your way.'), findsOneWidget);
          expect(find.text('Map ready'), findsNothing);
          await t.pump(const Duration(milliseconds: 1051));
          await t.pumpAndSettle();
          expect(splash, findsNothing);
          expect(find.byType(WaybiBird), findsNothing);
          expect(find.text('Map ready'), findsOneWidget);
          await t.pumpWidget(
            app(
              brightness == Brightness.light
                  ? Brightness.dark
                  : Brightness.light,
            ),
          );
          await t.pumpAndSettle();
          expect(splash, findsNothing);
          expect(find.text('Map ready'), findsOneWidget);
        },
      );
    }
  }
}
