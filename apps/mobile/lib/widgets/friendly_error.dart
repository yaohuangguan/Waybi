import 'dart:async';

import 'package:http/http.dart' as http;

/// Server error codes the app explains to people (see the Worker's
/// `http_errors.ts` and auth/abuse guards).
abstract final class WaybiErrorCode {
  static const loginLocked = 'LOGIN_LOCKED';
  static const rateLimited = 'RATE_LIMITED';
  static const subscriptionCancelFailed = 'SUBSCRIPTION_CANCEL_FAILED';
  static const internal = 'INTERNAL_ERROR';
  static const upstream = 'UPSTREAM_UNAVAILABLE';
  static const invalidRequest = 'INVALID_REQUEST';
  static const signInRequired = 'SIGN_IN_REQUIRED';
  static const plusRequired = 'PLUS_REQUIRED';
  static const billingUnavailable = 'BILLING_UNAVAILABLE';
  static const billingError = 'BILLING_ERROR';
  static const voicePackLimit = 'VOICE_PACK_LIMIT';
  static const voicePackNotFound = 'VOICE_PACK_NOT_FOUND';
  static const voiceSharingUnavailable = 'VOICE_SHARING_UNAVAILABLE';
  static const voiceConsentRequired = 'CONSENT_REQUIRED';
  static const voicePackTooLarge = 'VOICE_PACK_TOO_LARGE';
  static const voiceClipInvalid = 'INVALID_CLIP';
  static const voiceClipIntegrity = 'CLIP_INTEGRITY';
  static const voicePackPurgeFailed = 'VOICE_PACK_PURGE_FAILED';
  static const voicePackDeleteFailed = 'VOICE_PACK_DELETE_FAILED';
}

/// Reads `statusCode`/`status`, `code` and `retryAfter` from typed request
/// errors without depending on a particular exception class: the data layer
/// may wrap API failures in its own type.
Object? _field(Object error, String name) {
  try {
    final dynamic value = error;
    return switch (name) {
      'statusCode' => value.statusCode,
      'status' => value.status,
      'code' => value.code,
      'retryAfter' => value.retryAfter,
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

/// The HTTP status carried by [error], from a typed field or its message.
int? errorStatus(Object? error) {
  if (error == null) return null;
  for (final name in const ['statusCode', 'status']) {
    final value = _field(error, name);
    if (value is int && value >= 100 && value < 600) return value;
  }
  final match = RegExp(r'\b([45]\d\d)\b').firstMatch(_stripPrefix('$error'));
  return match == null ? null : int.parse(match.group(1)!);
}

/// The server error code carried by [error] (typed field, a code in the
/// message, or a known server message).
String? errorCode(Object? error) {
  if (error == null) return null;
  final typed = _field(error, 'code');
  if (typed is String && RegExp(r'^[A-Z][A-Z_]+$').hasMatch(typed)) {
    return typed;
  }
  final message = _stripPrefix('$error');
  final inline = RegExp(r'\b([A-Z]{3,}(?:_[A-Z]+)+)\b').firstMatch(message);
  if (inline != null) return inline.group(1);
  return _codeForServerMessage(message);
}

/// Seconds to wait before retrying, when the error says so.
int? errorRetryAfterSeconds(Object? error) {
  if (error == null) return null;
  final value = _field(error, 'retryAfter');
  if (value is num && value > 0) return value.ceil();
  final match = RegExp(
    r'retry[- ]?after\D{0,3}(\d{1,5})',
    caseSensitive: false,
  ).firstMatch('$error');
  return match == null ? null : int.parse(match.group(1)!);
}

/// Turns an exception into a short message a person can act on.
///
/// Errors are mapped by server code and HTTP status first; 5xx and coded
/// errors never show the server's text. Only readable, uncoded 4xx-style
/// messages (for example "Code is invalid or expired") pass through, and only
/// in English; Chinese never shows untranslated English and uses [fallback]
/// (already localized) or a generic retry message instead.
String friendlyErrorMessage(
  Object? error,
  String language, {
  String? fallback,
}) {
  final zh = language == 'zh';
  String t(String en, String cn) => zh ? cn : en;
  final generic =
      fallback ?? t('Something went wrong. Please try again.', '暂时无法完成，请稍后重试。');
  if (error == null) return generic;

  final type = error.runtimeType.toString();
  if (error is TimeoutException) {
    return t(
      'Waybi took too long to respond. Check your connection and try again.',
      '响应超时，请检查网络后重试。',
    );
  }
  if (error is http.ClientException ||
      type.contains('SocketException') ||
      type.contains('HandshakeException') ||
      type.contains('HttpException')) {
    return t(
      'Can’t reach Waybi right now. Check your connection and try again.',
      '暂时无法连接 Waybi，请检查网络后重试。',
    );
  }
  if (error is FormatException) {
    return t(
      'Waybi sent an unexpected response. Please try again shortly.',
      '服务返回了异常数据，请稍后重试。',
    );
  }

  final code = errorCode(error);
  final retryAfter = errorRetryAfterSeconds(error);
  switch (code) {
    case WaybiErrorCode.loginLocked:
      return t(
        'Too many sign-in attempts. Wait 15 minutes, or sign in with an email code instead.',
        '登录尝试次数过多。请 15 分钟后再试，或改用邮箱验证码登录。',
      );
    case WaybiErrorCode.rateLimited:
      final wait = retryAfter == null
          ? t('a moment', '片刻')
          : retryAfter >= 90
          ? t(
              '${(retryAfter / 60).ceil()} min',
              '${(retryAfter / 60).ceil()} 分钟',
            )
          : t('$retryAfter s', '$retryAfter 秒');
      return t(
        'Too many requests. Please wait $wait and try again.',
        '请求过于频繁，请等待$wait后重试。',
      );
    case WaybiErrorCode.subscriptionCancelFailed:
      return t(
        'Your subscription couldn’t be cancelled, so your account was not deleted. Please try again.',
        '订阅未能取消，因此账号没有被删除。请重试。',
      );
    case WaybiErrorCode.signInRequired:
      return t('Please sign in to continue.', '请先登录后继续。');
    case WaybiErrorCode.plusRequired:
      return t('This needs Waybi Plus.', '此功能需要 Waybi Plus。');
    case WaybiErrorCode.billingUnavailable:
    case WaybiErrorCode.billingError:
      return t(
        'Subscriptions are temporarily unavailable. Please try again later.',
        '订阅服务暂时不可用，请稍后重试。',
      );
    case WaybiErrorCode.voicePackLimit:
      return t(
        'You already share 5 voices. Revoke one to share another.',
        '你已分享 5 个语音。撤销一个后才能再分享。',
      );
    case WaybiErrorCode.voicePackNotFound:
      return t(
        'That voice code isn’t valid or has been revoked. Check it, or ask for a new one.',
        '这个语音代码无效或已被撤销。请核对，或向对方重新索取。',
      );
    case WaybiErrorCode.voiceSharingUnavailable:
      return t(
        'Voice sharing is temporarily unavailable. Please try again later.',
        '语音分享暂时不可用，请稍后重试。',
      );
    case WaybiErrorCode.voiceConsentRequired:
      return t(
        'Confirm this is your own voice and that you agree to share it.',
        '请确认这是你本人的声音并同意分享。',
      );
    case WaybiErrorCode.voicePackTooLarge:
      return t(
        'Your recordings are too large to share. Re-record the longest phrases and try again.',
        '录音太大，无法分享。请重录较长的短语后再试。',
      );
    case WaybiErrorCode.voiceClipInvalid:
      return t(
        'One of your recordings can’t be shared. Re-record it and try again.',
        '有一段录音无法分享，请重录后再试。',
      );
    case WaybiErrorCode.voiceClipIntegrity:
      return t(
        'A recording was damaged in transfer. Please try again.',
        '有录音在传输中损坏，请重试。',
      );
    case WaybiErrorCode.voicePackPurgeFailed:
      return t(
        'The code was revoked, but some recordings are still being removed. Please try again.',
        '代码已撤销，但部分录音尚未删除，请重试。',
      );
    case WaybiErrorCode.voicePackDeleteFailed:
      return t(
        'Your shared voice recordings couldn’t be removed, so your account was not deleted. Please try again.',
        '已分享的语音录音未能删除，因此账号没有被删除。请重试。',
      );
    case WaybiErrorCode.invalidRequest:
      return generic;
    case WaybiErrorCode.internal:
    case WaybiErrorCode.upstream:
      return _serviceTrouble(t);
  }

  final status = errorStatus(error);
  if (status != null) {
    if (status == 401 || status == 403) {
      return t('Please sign in again to continue.', '请重新登录后继续。');
    }
    if (status == 404) {
      return t('That item is no longer available.', '该内容已不可用。');
    }
    if (status == 408 || status == 429) {
      return t('Waybi is busy. Wait a moment and try again.', '请求过于频繁，请稍候再试。');
    }
    if (status >= 500) return _serviceTrouble(t);
  }

  final message = _stripPrefix('$error');
  final known = _knownMessages[message];
  if (known != null) return zh ? known : message;
  if (code != null || message.isEmpty || _looksTechnical(message, type)) {
    return generic;
  }
  if (zh) return _hasCjk(message) ? message : generic;
  return message;
}

String _serviceTrouble(String Function(String, String) t) => t(
  'Waybi is having trouble right now. Please try again shortly.',
  'Waybi 服务暂时不可用，请稍后重试。',
);

String _stripPrefix(String raw) {
  var message = raw.trim();
  for (final prefix in const [
    'Bad state:',
    'Exception:',
    'Invalid argument(s):',
    'Invalid argument:',
  ]) {
    if (message.startsWith(prefix)) {
      message = message.substring(prefix.length).trim();
    }
  }
  return message;
}

/// Generic server texts (5xx bodies, lockout and cancel failures) that may
/// reach the app without their code.
String? _codeForServerMessage(String message) {
  final lower = message.toLowerCase();
  if (lower == 'internal error' || lower.startsWith('internal server error')) {
    return WaybiErrorCode.internal;
  }
  if (lower.startsWith('upstream service unavailable')) {
    return WaybiErrorCode.upstream;
  }
  if (lower.startsWith('too many attempts')) return WaybiErrorCode.loginLocked;
  if (lower.startsWith('too many requests')) return WaybiErrorCode.rateLimited;
  if (lower.contains('subscription could not be cancelled')) {
    return WaybiErrorCode.subscriptionCancelFailed;
  }
  if (lower == 'invalid request encoding') return WaybiErrorCode.invalidRequest;
  return null;
}

bool _hasCjk(String text) => RegExp(r'[㐀-鿿]').hasMatch(text);

bool _looksTechnical(String message, String type) {
  if (message.length > 160) return true;
  const markers = [
    'Instance of',
    'Exception',
    'Error:',
    'Null check',
    'is not a subtype',
    'NoSuchMethod',
    'RangeError',
    'Stack',
    'dart:',
    'package:',
    'http://',
    'https://',
    'response',
    'Unexpected',
    'Invalid value',
    'Failed host lookup',
    'errno',
    'requestId',
    'D1_',
    'SQLITE',
  ];
  if (markers.any(message.contains)) return true;
  // Private SDK types (`_TypeError`, `_CastError`…) are programming errors;
  // `Exception('…')` is `_Exception` and may carry a readable message.
  return type.startsWith('_') && type != '_Exception';
}

/// Messages the app and server write for people, with translations.
const _knownMessages = <String, String>{
  'Sign in to edit your profile': '请先登录再编辑资料。',
  'Sign in again before deleting the account': '删除账号前请重新登录。',
  'Sign in to sync journeys': '请先登录再同步旅程。',
  'Sign in to sync favorite places': '请先登录再同步收藏地点。',
  'Sign in to save a review': '请先登录再保存评价。',
  'Sign in to use Route Watch': '请先登录再使用路线监控。',
  'The account changed': '账号已切换，请重试。',
  'Sign-in session was not returned': '未能完成登录，请重试。',
  'Google sign-in is unavailable on this device': '此设备暂不支持 Google 登录。',
  'Google did not return an ID token': 'Google 登录未完成，请重试。',
  'Invalid credentials': '邮箱或密码不正确。',
  'Apple authorization could not be revoked. Please retry account deletion.':
      'Apple 授权未能撤销，账号没有被删除。请重试。',
};
