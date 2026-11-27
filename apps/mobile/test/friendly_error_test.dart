import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:waybi_mobile/widgets/friendly_error.dart';

/// A typed request error like the data layer may throw.
class ApiFailure implements Exception {
  ApiFailure(this.statusCode, this.message, {this.code, this.retryAfter});
  final int statusCode;
  final String message;
  final String? code;
  final int? retryAfter;
  @override
  String toString() => message;
}

class SocketException implements Exception {
  @override
  String toString() => 'SocketException: Failed host lookup: waybi.co';
}

void main() {
  test('network failures become connection advice', () {
    expect(
      friendlyErrorMessage(http.ClientException('Connection reset'), 'en'),
      startsWith('Can’t reach Waybi'),
    );
    expect(
      friendlyErrorMessage(SocketException(), 'zh'),
      '暂时无法连接 Waybi，请检查网络后重试。',
    );
    expect(
      friendlyErrorMessage(TimeoutException('slow'), 'en'),
      startsWith('Waybi took too long'),
    );
    expect(
      friendlyErrorMessage(const FormatException('<html>'), 'zh'),
      '服务返回了异常数据，请稍后重试。',
    );
  });

  test('status codes never show raw server text', () {
    expect(
      friendlyErrorMessage(StateError('Road report failed: 500'), 'zh'),
      'Waybi 服务暂时不可用，请稍后重试。',
    );
    expect(
      friendlyErrorMessage(StateError('Account request failed (503)'), 'en'),
      'Waybi is having trouble right now. Please try again shortly.',
    );
    expect(
      friendlyErrorMessage(ApiFailure(500, 'Internal error'), 'en'),
      'Waybi is having trouble right now. Please try again shortly.',
    );
    expect(
      friendlyErrorMessage(StateError('Internal error'), 'en'),
      'Waybi is having trouble right now. Please try again shortly.',
    );
    expect(
      friendlyErrorMessage(
        StateError('Upstream service unavailable. Please retry shortly.'),
        'en',
      ),
      'Waybi is having trouble right now. Please try again shortly.',
    );
    expect(
      friendlyErrorMessage(ApiFailure(401, 'Not signed in'), 'en'),
      'Please sign in again to continue.',
    );
    expect(
      friendlyErrorMessage(StateError('Request failed 404'), 'zh'),
      '该内容已不可用。',
    );
    expect(
      friendlyErrorMessage(StateError('Request failed 429'), 'en'),
      'Waybi is busy. Wait a moment and try again.',
    );
  });

  test('server codes map to specific advice', () {
    final locked = ApiFailure(
      429,
      'Too many attempts. Try again in 15 minutes, or sign in with an email code.',
      code: 'LOGIN_LOCKED',
    );
    expect(errorCode(locked), WaybiErrorCode.loginLocked);
    expect(errorStatus(locked), 429);
    expect(friendlyErrorMessage(locked, 'zh'), contains('邮箱验证码'));
    expect(
      errorCode(StateError('Too many attempts. Try again in 15 minutes.')),
      WaybiErrorCode.loginLocked,
    );
    final limited = ApiFailure(
      429,
      'Too many requests',
      code: 'RATE_LIMITED',
      retryAfter: 30,
    );
    expect(errorRetryAfterSeconds(limited), 30);
    expect(friendlyErrorMessage(limited, 'en'), contains('30 s'));
    expect(
      friendlyErrorMessage(
        ApiFailure(429, 'x', code: 'RATE_LIMITED', retryAfter: 600),
        'zh',
      ),
      contains('10 分钟'),
    );
    expect(
      friendlyErrorMessage(StateError('Too many requests'), 'en'),
      contains('a moment'),
    );
    expect(errorRetryAfterSeconds(StateError('retry-after: 12')), 12);
    expect(errorRetryAfterSeconds(null), isNull);
    expect(
      friendlyErrorMessage(
        StateError(
          'Your subscription could not be cancelled. Please retry account deletion.',
        ),
        'en',
      ),
      startsWith('Your subscription couldn’t be cancelled'),
    );
    expect(
      errorCode(StateError('SUBSCRIPTION_CANCEL_FAILED')),
      WaybiErrorCode.subscriptionCancelFailed,
    );
    for (final code in [
      'SIGN_IN_REQUIRED',
      'PLUS_REQUIRED',
      'BILLING_UNAVAILABLE',
      'BILLING_ERROR',
      'INVALID_REQUEST',
      'UPSTREAM_UNAVAILABLE',
      'INTERNAL_ERROR',
    ]) {
      final message = friendlyErrorMessage(
        ApiFailure(400, 'raw $code text', code: code),
        'en',
      );
      expect(message, isNot(contains('raw')), reason: code);
    }
    expect(
      friendlyErrorMessage(StateError('Something SOME_NEW_CODE'), 'en'),
      'Something went wrong. Please try again.',
    );
  });

  test('readable messages pass through in English only', () {
    expect(
      friendlyErrorMessage(StateError('Code is invalid or expired'), 'en'),
      'Code is invalid or expired',
    );
    expect(
      friendlyErrorMessage(StateError('Code is invalid or expired'), 'zh'),
      '暂时无法完成，请稍后重试。',
    );
    expect(
      friendlyErrorMessage(
        StateError('Code is invalid or expired'),
        'zh',
        fallback: '请重试',
      ),
      '请重试',
    );
    expect(friendlyErrorMessage(StateError('验证码已过期'), 'zh'), '验证码已过期');
    expect(
      friendlyErrorMessage(StateError('Sign in to use Route Watch'), 'zh'),
      '请先登录再使用路线监控。',
    );
    expect(
      friendlyErrorMessage(StateError('Invalid credentials'), 'en'),
      'Invalid credentials',
    );
    expect(
      friendlyErrorMessage(Exception('Watch paused'), 'en'),
      'Watch paused',
    );
  });

  test('programming errors and technical text stay hidden', () {
    expect(
      friendlyErrorMessage(null, 'en'),
      'Something went wrong. Please try again.',
    );
    expect(
      friendlyErrorMessage(StateError('Invalid account response'), 'en'),
      'Something went wrong. Please try again.',
    );
    expect(
      friendlyErrorMessage(TypeError(), 'en', fallback: 'Try again'),
      'Try again',
    );
    expect(
      friendlyErrorMessage(StateError('x' * 200), 'en'),
      'Something went wrong. Please try again.',
    );
    expect(
      friendlyErrorMessage(StateError('D1_ERROR: no such table'), 'en'),
      'Something went wrong. Please try again.',
    );
    expect(
      friendlyErrorMessage(StateError(''), 'en'),
      'Something went wrong. Please try again.',
    );
    expect(errorStatus(null), isNull);
    expect(errorCode(null), isNull);
  });
}
