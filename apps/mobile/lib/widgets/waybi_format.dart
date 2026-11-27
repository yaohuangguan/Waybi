import 'package:flutter/widgets.dart';

/// Shared, locale-aware formatting for widgets that still use the
/// per-widget `_text(en, zh)` pattern. Only `en` and `zh` are supported.

/// The widget's explicit language, or the app locale when none was passed.
String waybiLanguageOf(BuildContext context, [String? explicit]) {
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final locale = Localizations.maybeLocaleOf(context);
  return locale?.languageCode == 'zh' ? 'zh' : 'en';
}

bool _zh(String language) => language == 'zh';

/// Metres below 1 km, one decimal below 10 km, whole kilometres beyond.
String formatDistance(num? metres, String language) {
  if (metres == null || !metres.isFinite) return '—';
  final safe = metres < 0 ? 0 : metres;
  if (safe < 1000) {
    return '${safe.round()} ${_zh(language) ? '米' : 'm'}';
  }
  final km = safe / 1000;
  final value = km < 10 ? km.toStringAsFixed(1) : km.round().toString();
  return '$value ${_zh(language) ? '公里' : 'km'}';
}

/// "12 min", "1 h 5 min" / "12 分钟", "1 小时 5 分钟".
String formatDuration(int seconds, String language) {
  final minutes = (seconds / 60).ceil().clamp(1, 99999);
  if (minutes < 60) return _zh(language) ? '$minutes 分钟' : '$minutes min';
  final hours = minutes ~/ 60;
  final remain = minutes % 60;
  if (_zh(language)) {
    return remain == 0 ? '$hours 小时' : '$hours 小时 $remain 分钟';
  }
  return remain == 0 ? '$hours h' : '$hours h $remain min';
}

String speedUnit(String language) => _zh(language) ? '公里/时' : 'km/h';

const _monthsEn = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Day-month date as used in New Zealand ("26 Nov"), with the year when it is
/// not the current one. Chinese uses "11月26日".
String formatShortDate(DateTime date, String language, {DateTime? now}) {
  final local = date.toLocal();
  final current = (now ?? DateTime.now()).toLocal();
  final sameYear = local.year == current.year;
  if (_zh(language)) {
    final day = '${local.month}月${local.day}日';
    return sameYear ? day : '${local.year}年$day';
  }
  final day = '${local.day} ${_monthsEn[local.month - 1]}';
  return sameYear ? day : '$day ${local.year}';
}

/// "Just now", "5 min ago", "3 h ago", "2 days ago", then a short date.
String formatRelativeTime(DateTime? time, String language, {DateTime? now}) {
  if (time == null) return '';
  final reference = now ?? DateTime.now();
  final delta = reference.difference(time.toLocal());
  final zh = _zh(language);
  if (delta.isNegative || delta.inMinutes < 1) return zh ? '刚刚' : 'Just now';
  if (delta.inMinutes < 60) {
    return zh ? '${delta.inMinutes} 分钟前' : '${delta.inMinutes} min ago';
  }
  if (delta.inHours < 24) {
    return zh ? '${delta.inHours} 小时前' : '${delta.inHours} h ago';
  }
  if (delta.inDays < 7) {
    if (zh) return '${delta.inDays} 天前';
    return delta.inDays == 1 ? '1 day ago' : '${delta.inDays} days ago';
  }
  return formatShortDate(time, language, now: reference);
}

/// Parses an ISO string or epoch (seconds or milliseconds) from an API map.
DateTime? parseApiTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is num) {
    final milliseconds = value > 100000000000 ? value : value * 1000;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds.round());
  }
  final text = value.toString().trim();
  final asNumber = num.tryParse(text);
  if (asNumber != null) return parseApiTime(asNumber);
  return DateTime.tryParse(text);
}
