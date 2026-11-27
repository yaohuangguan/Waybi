import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/theme/waybi_theme.dart';

import 'support/contrast.dart';

void main() {
  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    final theme = dark ? WaybiTheme.dark : WaybiTheme.light;
    final status = theme.extension<WaybiStatusColors>()!;
    final surfaces = dark
        ? [
            theme.colorScheme.surface,
            theme.scaffoldBackgroundColor,
            WaybiColors.darkSurface,
          ]
        : [
            theme.colorScheme.surface,
            theme.scaffoldBackgroundColor,
            WaybiColors.mist,
            WaybiColors.ice,
          ];

    test('$name status colours meet WCAG AA for text', () {
      final roles = {
        'success': (
          status.success,
          status.onSuccess,
          status.successContainer,
          status.onSuccessContainer,
        ),
        'warning': (
          status.warning,
          status.onWarning,
          status.warningContainer,
          status.onWarningContainer,
        ),
        'info': (
          status.info,
          status.onInfo,
          status.infoContainer,
          status.onInfoContainer,
        ),
        'danger': (
          status.danger,
          status.onDanger,
          status.dangerContainer,
          status.onDangerContainer,
        ),
      };
      for (final MapEntry(key: role, value: c) in roles.entries) {
        for (final surface in surfaces) {
          expect(
            contrastRatio(c.$1, surface),
            greaterThanOrEqualTo(4.5),
            reason: '$name $role on $surface',
          );
        }
        expect(contrastRatio(c.$2, c.$1), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(c.$4, c.$3), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(c.$1, c.$3), greaterThanOrEqualTo(4.5));
      }
    });

    test('$name scheme error and secondary text stay readable', () {
      final scheme = theme.colorScheme;
      for (final surface in surfaces) {
        expect(contrastRatio(scheme.error, surface), greaterThanOrEqualTo(4.5));
        expect(
          contrastRatio(scheme.onSurfaceVariant, surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastRatio(scheme.primary, surface),
          greaterThanOrEqualTo(4.5),
        );
      }
      expect(
        contrastRatio(scheme.onError, scheme.error),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('$name text theme never drops below 12 pt', () {
      final styles = theme.textTheme;
      for (final style in [
        styles.bodyLarge,
        styles.bodyMedium,
        styles.bodySmall,
        styles.labelLarge,
        styles.labelMedium,
        styles.labelSmall,
        styles.titleSmall,
      ]) {
        expect(style!.fontSize, greaterThanOrEqualTo(WaybiTextSize.caption));
      }
      final drive = theme.extension<WaybiDriveTypography>()!;
      for (final style in [
        drive.distance,
        drive.instruction,
        drive.secondary,
        drive.value,
        drive.notice,
      ]) {
        expect(style.fontSize, greaterThanOrEqualTo(16));
      }
      expect(drive.label.fontSize, greaterThanOrEqualTo(WaybiTextSize.caption));
      expect(drive.unit.fontSize, greaterThanOrEqualTo(WaybiTextSize.caption));
    });
  }

  test('always-dark guidance ink keeps contrast in both themes', () {
    for (final colour in [
      WaybiInk.text,
      WaybiInk.muted,
      WaybiInk.accent,
      WaybiInk.danger,
      WaybiInk.success,
      WaybiInk.warning,
    ]) {
      expect(
        contrastRatio(colour, WaybiInk.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(contrastRatio(colour, WaybiInk.raised), greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('context helpers fall back to brightness defaults', (t) async {
    late WaybiStatusColors plainLight, plainDark, themed;
    late WaybiDriveTypography type;
    late bool darkFlag;
    Widget probe(ValueSetter<BuildContext> read) => Builder(
      builder: (context) {
        read(context);
        return const SizedBox();
      },
    );
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(),
        home: probe((c) {
          plainLight = c.status;
          type = c.driveType;
        }),
      ),
    );
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: probe((c) {
          plainDark = c.status;
          darkFlag = c.isDark;
        }),
      ),
    );
    await t.pumpAndSettle();
    await t.pumpWidget(
      MaterialApp(
        theme: WaybiTheme.darkFor('zh'),
        home: probe((c) {
          themed = c.status;
          expect(c.colors, Theme.of(c).colorScheme);
          expect(c.textStyles.bodySmall!.fontSize, 12);
        }),
      ),
    );
    expect(plainLight, same(WaybiStatusColors.light));
    expect(plainDark, same(WaybiStatusColors.dark));
    expect(themed.danger, WaybiStatusColors.dark.danger);
    expect(type, same(WaybiDriveTypography.standard));
    expect(darkFlag, isTrue);
  });

  test('extensions copy and interpolate', () {
    const light = WaybiStatusColors.light;
    final copy = light.copyWith(warning: Colors.orange);
    expect(copy.warning, Colors.orange);
    expect(copy.success, light.success);
    expect(light.copyWith(), isA<WaybiStatusColors>());
    expect(light.lerp(null, .5), same(light));
    expect(
      light.lerp(WaybiStatusColors.dark, 1).danger,
      WaybiStatusColors.dark.danger,
    );
    expect(light.lerp(WaybiStatusColors.dark, 0).info, light.info);

    const drive = WaybiDriveTypography.standard;
    final bigger = drive.copyWith(value: const TextStyle(fontSize: 40));
    expect(bigger.value.fontSize, 40);
    expect(drive.copyWith().label, drive.label);
    expect(drive.lerp(null, .3), same(drive));
    expect(drive.lerp(bigger, 1).value.fontSize, 40);
  });
}
