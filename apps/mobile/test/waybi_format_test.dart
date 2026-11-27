import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/widgets/waybi_format.dart';

void main() {
  test('distances switch to km and localize units', () {
    expect(formatDistance(null, 'en'), '—');
    expect(formatDistance(double.nan, 'en'), '—');
    expect(formatDistance(-4, 'en'), '0 m');
    expect(formatDistance(999.4, 'en'), '999 m');
    expect(formatDistance(1250, 'en'), '1.3 km');
    expect(formatDistance(1250, 'zh'), '1.3 公里');
    expect(formatDistance(12600, 'en'), '13 km');
    expect(formatDistance(80, 'zh'), '80 米');
  });

  test('durations are localized', () {
    expect(formatDuration(20, 'en'), '1 min');
    expect(formatDuration(1500, 'zh'), '25 分钟');
    expect(formatDuration(3600, 'en'), '1 h');
    expect(formatDuration(3900, 'en'), '1 h 5 min');
    expect(formatDuration(7200, 'zh'), '2 小时');
    expect(formatDuration(7500, 'zh'), '2 小时 5 分钟');
    expect(speedUnit('en'), 'km/h');
    expect(speedUnit('zh'), '公里/时');
  });

  test('dates are day-month for New Zealand and 月日 in Chinese', () {
    final now = DateTime(2026, 11, 26, 12);
    expect(formatShortDate(DateTime(2026, 3, 4), 'en', now: now), '4 Mar');
    expect(formatShortDate(DateTime(2026, 3, 4), 'zh', now: now), '3月4日');
    expect(
      formatShortDate(DateTime(2025, 12, 31), 'en', now: now),
      '31 Dec 2025',
    );
    expect(
      formatShortDate(DateTime(2025, 12, 31), 'zh', now: now),
      '2025年12月31日',
    );
  });

  test('relative times', () {
    final now = DateTime(2026, 11, 26, 12);
    expect(formatRelativeTime(null, 'en', now: now), '');
    expect(
      formatRelativeTime(now.add(const Duration(minutes: 3)), 'en', now: now),
      'Just now',
    );
    expect(
      formatRelativeTime(
        now.subtract(const Duration(seconds: 20)),
        'zh',
        now: now,
      ),
      '刚刚',
    );
    expect(
      formatRelativeTime(
        now.subtract(const Duration(minutes: 5)),
        'en',
        now: now,
      ),
      '5 min ago',
    );
    expect(
      formatRelativeTime(
        now.subtract(const Duration(minutes: 5)),
        'zh',
        now: now,
      ),
      '5 分钟前',
    );
    expect(
      formatRelativeTime(
        now.subtract(const Duration(hours: 3)),
        'en',
        now: now,
      ),
      '3 h ago',
    );
    expect(
      formatRelativeTime(
        now.subtract(const Duration(hours: 3)),
        'zh',
        now: now,
      ),
      '3 小时前',
    );
    expect(
      formatRelativeTime(now.subtract(const Duration(days: 1)), 'en', now: now),
      '1 day ago',
    );
    expect(
      formatRelativeTime(now.subtract(const Duration(days: 4)), 'en', now: now),
      '4 days ago',
    );
    expect(
      formatRelativeTime(now.subtract(const Duration(days: 4)), 'zh', now: now),
      '4 天前',
    );
    expect(formatRelativeTime(DateTime(2026, 10, 2), 'en', now: now), '2 Oct');
  });

  test('API times accept ISO strings and epochs', () {
    final iso = DateTime.utc(2026, 11, 1, 8);
    expect(parseApiTime(null), isNull);
    expect(parseApiTime(iso), iso);
    expect(parseApiTime('2026-11-01T08:00:00Z'), iso);
    expect(parseApiTime(iso.millisecondsSinceEpoch), iso.toLocal());
    expect(parseApiTime(iso.millisecondsSinceEpoch ~/ 1000), iso.toLocal());
    expect(
      parseApiTime('${iso.millisecondsSinceEpoch ~/ 1000}'),
      iso.toLocal(),
    );
    expect(parseApiTime('not a date'), isNull);
  });

  testWidgets('language defaults to the app locale', (t) async {
    final seen = <String>[];
    for (final locale in const [Locale('zh'), Locale('en')]) {
      await t.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) {
              seen
                ..add(waybiLanguageOf(context))
                ..add(waybiLanguageOf(context, 'zh'));
              return const SizedBox();
            },
          ),
        ),
      );
    }
    expect(seen, ['zh', 'zh', 'en', 'zh']);
  });
}
