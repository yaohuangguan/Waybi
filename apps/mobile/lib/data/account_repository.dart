import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class AccountProfile {
  const AccountProfile({
    required this.email,
    required this.displayName,
    required this.providers,
    required this.routes,
    required this.places,
    required this.reviews,
    required this.recentDestinations,
    required this.plan,
    this.id = '',
    this.subscriptionSource,
    this.subscriptionExpiresAt,
  });

  final String email;
  final String displayName;
  final List<String> providers;
  final List<Map<String, dynamic>> routes;
  final List<Map<String, dynamic>> places;
  final List<Map<String, dynamic>> reviews;
  final List<Map<String, dynamic>> recentDestinations;
  final String plan;
  final String id;
  final String? subscriptionSource;
  final DateTime? subscriptionExpiresAt;

  bool get isPlus => plan == 'plus';

  factory AccountProfile.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> list(String key) =>
        (json[key] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
    return AccountProfile(
      email: (json['user'] as Map<String, dynamic>?)?['email'] as String? ?? '',
      displayName:
          (json['user'] as Map<String, dynamic>?)?['displayName'] as String? ??
          '',
      providers:
          ((json['user'] as Map<String, dynamic>?)?['providers']
                      as List<dynamic>? ??
                  const [])
              .whereType<String>()
              .toList(),
      routes: list('routeHistory'),
      places: list('savedPlaces'),
      reviews: list('reviews'),
      recentDestinations: list('recentDestinations'),
      id: (json['user'] as Map<String, dynamic>?)?['id'] as String? ?? '',
      subscriptionSource:
          (json['subscription'] as Map<String, dynamic>?)?['source'] as String?,
      subscriptionExpiresAt:
          (json['subscription'] as Map<String, dynamic>?)?['expiresAt'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              ((json['subscription'] as Map<String, dynamic>)['expiresAt']
                      as num)
                  .toInt(),
            )
          : null,
      plan:
          (json['subscription'] as Map<String, dynamic>?)?['plan'] as String? ??
          'free',
    );
  }
}

class AccountRepository extends ChangeNotifier {
  AccountRepository({http.Client? client, FlutterSecureStorage? storage})
    : _client = client ?? http.Client(),
      _storage = storage ?? const FlutterSecureStorage();

  static const _storageKey = 'waybi_session';
  static const _legacyStorageKey = 'kiwi_lens_session';
  static const _googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '858928595374-slrbiedfhivmnliv0d4uvpn0n8rh21tu.apps.googleusercontent.com',
  );
  static const _googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '858928595374-ht0e455sfe58a2cfgovjka7t40cku2ss.apps.googleusercontent.com',
  );
  Future<void>? _googleReady;
  Future<void> _initializeGoogle() =>
      _googleReady ??= GoogleSignIn.instance.initialize(
        clientId: defaultTargetPlatform == TargetPlatform.iOS
            ? _googleIosClientId
            : null,
        serverClientId: _googleServerClientId,
      );
  final http.Client _client;
  final FlutterSecureStorage _storage;
  String? _session;
  AccountProfile? profile;
  bool loading = false;

  bool get signedIn => _session != null;
  String? get sessionToken => _session;

  Future<http.Response> _request(
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    final headers = <String, String>{
      if (_session != null) 'cookie': 'waybi_session=$_session',
      if (method != 'GET') ...{
        'content-type': 'application/json',
        'x-waybi-client': 'mobile',
      },
    };
    final request = http.Request(method, Uri.parse('$workerBaseUrl$path'))
      ..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final streamed = await _client.send(request);
    return http.Response.fromStream(streamed);
  }

  Map<String, dynamic> _body(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Invalid account response');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        decoded['error'] as String? ??
            'Account request failed (${response.statusCode})',
      );
    }
    return decoded;
  }

  Future<void> restore() async {
    try {
      _session = await _storage.read(key: _storageKey);
      if (_session == null) {
        _session = await _storage.read(key: _legacyStorageKey);
        if (_session != null) {
          await _storage.write(key: _storageKey, value: _session);
          await _storage.delete(key: _legacyStorageKey);
        }
      }
      if (_session == null) return;
      final response = await _request('/api/auth/me');
      if (response.statusCode == 401) {
        _session = null;
        await _storage.delete(key: _storageKey);
        await _storage.delete(key: _legacyStorageKey);
        return;
      }
      profile = AccountProfile.fromJson(_body(response));
      notifyListeners();
    } catch (_) {
      /* Guest navigation remains available while offline. */
    }
  }

  Future<void> authenticate(
    String email,
    String password, {
    required bool register,
  }) async {
    loading = true;
    notifyListeners();
    try {
      final response = await _request(
        register ? '/api/auth/register' : '/api/auth/login',
        method: 'POST',
        body: {
          'email': email.trim(),
          'password': password,
          'language': 'en',
          'voiceEnabled': true,
        },
      );
      final next = AccountProfile.fromJson(_body(response));
      final cookie = response.headers['set-cookie'] ?? '';
      final match = RegExp(r'(?:^|;\s*)waybi_session=([0-9a-f]{64})')
          .firstMatch(cookie);
      if (match == null) throw StateError('Sign-in session was not returned');
      _session = match.group(1);
      await _storage.write(key: _storageKey, value: _session);
      profile = next;
      notifyListeners();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> authenticateWithGoogle({bool link = false}) async {
    loading = true;
    notifyListeners();
    try {
      await _initializeGoogle();
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw StateError('Google sign-in is unavailable on this device');
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw StateError('Google did not return an ID token');
      }
      final response = await _request(
        link ? '/api/auth/google/link' : '/api/auth/google',
        method: 'POST',
        body: {'idToken': idToken},
      );
      final next = AccountProfile.fromJson(_body(response));
      if (!link) {
        final cookie = response.headers['set-cookie'] ?? '';
        final match = RegExp(r'(?:^|;\s*)waybi_session=([0-9a-f]{64})')
            .firstMatch(cookie);
        if (match == null) throw StateError('Sign-in session was not returned');
        _session = match.group(1);
        await _storage.write(key: _storageKey, value: _session);
      }
      profile = next;
      notifyListeners();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> submitRoadReport({
    required String type,
    required double latitude,
    required double longitude,
    double? headingDegrees,
    required String description,
  }) async {
    final response = await _request(
      '/api/road-reports',
      method: 'POST',
      body: {
        'type': type,
        'latitude': latitude,
        'longitude': longitude,
        'headingDegrees': headingDegrees,
        'description': description,
      },
    );
    if (response.statusCode != 201) {
      throw StateError('Road report failed: ${response.statusCode}');
    }
  }

  Future<void> updateDisplayName(String name) async {
    if (_session == null) throw StateError('Sign in to edit your profile');
    profile = AccountProfile.fromJson(
      _body(
        await _request(
          '/api/profile/details',
          method: 'PATCH',
          body: {'displayName': name.trim()},
        ),
      ),
    );
    notifyListeners();
  }

  Future<void> updatePreferences({
    required String language,
    required bool voiceEnabled,
  }) async {
    if (_session == null) return;
    profile = AccountProfile.fromJson(
      _body(
        await _request(
          '/api/profile',
          method: 'PATCH',
          body: {
            'language': language == 'zh-CN' || language == 'zh' ? 'zh' : 'en',
            'voiceEnabled': voiceEnabled,
          },
        ),
      ),
    );
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await _request('/api/auth/logout', method: 'POST');
    } catch (_) {}
    _session = null;
    profile = null;
    if (_googleReady != null) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await _storage.delete(key: _storageKey);
    await _storage.delete(key: _legacyStorageKey);
    notifyListeners();
  }

  Future<Map<String, dynamic>> appleBillingConfig() async =>
      _body(await _request('/api/billing/apple/config'));

  Future<Map<String, dynamic>> verifyApplePurchase(
    String transactionId,
  ) async => _body(
    await _request(
      '/api/billing/apple/verify',
      method: 'POST',
      body: {'transactionId': transactionId},
    ),
  );

  Future<void> refresh() async {
    if (_session == null) return;
    profile = AccountProfile.fromJson(_body(await _request('/api/auth/me')));
    notifyListeners();
  }

  Future<void> recordDestination({
    required String label,
    required double latitude,
    required double longitude,
  }) async {
    if (_session == null) return;
    profile = AccountProfile.fromJson(
      _body(
        await _request(
          '/api/profile/destinations',
          method: 'POST',
          body: {'label': label, 'latitude': latitude, 'longitude': longitude},
        ),
      ),
    );
    notifyListeners();
  }

  Future<void> recordRoute({
    required String destinationName,
    required double latitude,
    required double longitude,
    required String mode,
    required int distanceMeters,
    required int durationSeconds,
  }) async {
    if (_session == null) return;
    profile = AccountProfile.fromJson(
      _body(
        await _request(
          '/api/profile/routes',
          method: 'POST',
          body: {
            'destinationName': destinationName,
            'latitude': latitude,
            'longitude': longitude,
            'mode': mode,
            'distanceMeters': distanceMeters,
            'durationSeconds': durationSeconds,
          },
        ),
      ),
    );
    notifyListeners();
  }

  Future<void> saveFavorite({
    required String placeId,
    required String name,
    required double latitude,
    required double longitude,
    required bool favorite,
  }) async {
    if (_session == null) throw StateError('Sign in to sync favorite places');
    profile = AccountProfile.fromJson(
      _body(
        await _request(
          '/api/profile/places',
          method: 'POST',
          body: {
            'placeId': placeId,
            'name': name,
            'address': '',
            'latitude': latitude,
            'longitude': longitude,
            'isFavorite': favorite,
            'note': '',
          },
        ),
      ),
    );
    notifyListeners();
  }

  Future<void> saveReview({
    required String placeId,
    required String placeName,
    required int rating,
    required String comment,
  }) async {
    if (_session == null) throw StateError('Sign in to save a review');
    profile = AccountProfile.fromJson(
      _body(
        await _request(
          '/api/profile/reviews',
          method: 'POST',
          body: {
            'placeId': placeId,
            'placeName': placeName,
            'rating': rating,
            'comment': comment,
          },
        ),
      ),
    );
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> routeWatchAlerts() async {
    if (_session == null) return const [];
    final body = _body(await _request('/api/route-watch-alerts'));
    return (body['alerts'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Future<void> markRouteWatchAlertsRead(List<String> ids) async {
    if (_session == null || ids.isEmpty) return;
    _body(
      await _request(
        '/api/route-watch-alerts/read',
        method: 'POST',
        body: {'ids': ids.take(50).toList(growable: false)},
      ),
    );
  }

  Future<List<Map<String, dynamic>>> routeWatches() async {
    if (_session == null) return const [];
    final body = _body(await _request('/api/route-watches'));
    return (body['watches'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Future<void> saveRouteWatch({
    required String label,
    required String originName,
    required double originLatitude,
    required double originLongitude,
    required String destinationName,
    required double latitude,
    required double longitude,
    required String routeProvider,
    required List<Map<String, double>> routePoints,
    required int durationSeconds,
    required int distanceMeters,
  }) async {
    if (_session == null) throw StateError('Sign in to use Route Watch');
    _body(
      await _request(
        '/api/route-watches',
        method: 'POST',
        body: {
          'label': label,
          'originName': originName,
          'origin': {'latitude': originLatitude, 'longitude': originLongitude},
          'destinationName': destinationName,
          'destination': {'latitude': latitude, 'longitude': longitude},
          'routeProvider': routeProvider,
          'routePoints': routePoints,
          'baselineDurationSeconds': durationSeconds,
          'baselineDistanceMeters': distanceMeters,
        },
      ),
    );
  }

  Future<void> deleteRouteWatch(String id) async {
    if (_session == null) return;
    _body(
      await _request(
        '/api/route-watches/${Uri.encodeComponent(id)}',
        method: 'DELETE',
      ),
    );
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}
