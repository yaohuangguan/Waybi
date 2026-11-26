import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A non-success or unreadable response, with a message that is safe to show.
/// It remains a [StateError] so existing call sites keep catching it.
class ApiException extends StateError {
  ApiException(super.message, {this.statusCode});
  final int? statusCode;

  @override
  String toString() => message;
}

/// The server asked this client to slow down (HTTP 429, or 503 with a
/// `Retry-After` header). Callers must not retry before [retryAfter].
class RateLimitedException extends ApiException {
  RateLimitedException(this.retryAfter, {int statusCode = 429})
    : super('Too many requests. Try again shortly.', statusCode: statusCode);
  final Duration retryAfter;

  @override
  String toString() =>
      'Rate limited ($statusCode); retry after ${retryAfter.inSeconds}s';
}

/// A request abandoned by its caller before it completed.
class RequestCancelledException implements Exception {
  const RequestCancelledException();

  @override
  String toString() => 'Request cancelled';
}

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// Parses `Retry-After` as delta-seconds or an IMF-fixdate HTTP date.
Duration? parseRetryAfter(String? value, {DateTime? now}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final seconds = int.tryParse(text);
  if (seconds != null) return seconds < 0 ? null : Duration(seconds: seconds);
  final match = RegExp(
    r'^[A-Za-z]{3},\s*(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+GMT$',
  ).firstMatch(text);
  final month = _months[match?.group(2)?.toLowerCase()];
  if (match == null || month == null) return null;
  final at = DateTime.utc(
    int.parse(match.group(3)!),
    month,
    int.parse(match.group(1)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
  final delay = at.difference((now ?? DateTime.now()).toUtc());
  return delay.isNegative ? Duration.zero : delay;
}

/// Throws [RateLimitedException] when the server is shedding load. A missing
/// or hostile header falls back to [fallback] and is clamped to [maximum].
void throwIfRateLimited(
  http.BaseResponse response, {
  Duration fallback = const Duration(seconds: 60),
  Duration maximum = const Duration(minutes: 15),
  DateTime? now,
}) {
  final status = response.statusCode;
  final header = response.headers['retry-after'];
  if (status != 429 && !(status == 503 && header != null)) return;
  var delay = parseRetryAfter(header, now: now) ?? fallback;
  if (delay > maximum) delay = maximum;
  throw RateLimitedException(delay, statusCode: status);
}

/// A user-facing `error` from a JSON body; never the text of an HTML page.
String? serverErrorMessage(http.Response response) {
  try {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final error = decoded is Map ? decoded['error'] : null;
    if (error is String && error.trim().isNotEmpty && error.length <= 240) {
      return error.trim();
    }
  } catch (_) {
    // Cloudflare and proxies answer 5xx with HTML.
  }
  return null;
}

/// Checks the status before decoding, so an HTML 502 page becomes a friendly
/// [ApiException] instead of a `FormatException` at the call site.
Object? decodeJsonResponse(
  http.Response response, {
  required String unavailable,
  Set<int> accept = const {200},
}) {
  throwIfRateLimited(response);
  if (!accept.contains(response.statusCode)) {
    throw ApiException(
      serverErrorMessage(response) ?? unavailable,
      statusCode: response.statusCode,
    );
  }
  try {
    return jsonDecode(utf8.decode(response.bodyBytes));
  } on FormatException {
    throw ApiException(unavailable, statusCode: response.statusCode);
  }
}

/// A GET whose socket is really aborted on timeout or cancellation, so a slow
/// server cannot accumulate overlapping requests from one device.
Future<http.Response> abortableGet(
  http.Client client,
  Uri uri, {
  Map<String, String>? headers,
  required Duration timeout,
  Future<void>? cancel,
}) {
  final trigger = Completer<void>();
  void abort() {
    if (!trigger.isCompleted) trigger.complete();
  }

  final request = http.AbortableRequest(
    'GET',
    uri,
    abortTrigger: trigger.future,
  );
  if (headers != null) request.headers.addAll(headers);
  final result = Completer<http.Response>();
  final timer = Timer(timeout, () {
    abort();
    if (!result.isCompleted) {
      result.completeError(TimeoutException('Request timed out', timeout));
    }
  });
  cancel?.then(
    (_) {
      abort();
      if (!result.isCompleted) {
        result.completeError(const RequestCancelledException());
      }
    },
    onError: (Object _) {
      /* A failing cancel signal is not a cancellation. */
    },
  );
  () async {
    final streamed = await client.send(request);
    return http.Response.fromStream(streamed);
  }().then(
    (response) {
      if (!result.isCompleted) result.complete(response);
    },
    onError: (Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    },
  );
  return result.future.whenComplete(timer.cancel);
}
