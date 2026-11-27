import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'http_guard.dart';
import '../domain/map_provider.dart';

/// Whether [id] can be sent to the Google `/api/place-details` endpoint.
///
/// Once the daily Google budget is spent, suggest and explore answer from
/// independent providers (`osm:node:1`, `wikipedia:en:2`, Geoapify hex ids).
/// Those ids must not be sent to Google Place Details.
bool isGooglePlaceId(String id, {String? provider}) {
  if (id.isEmpty || id.length > 512 || id.contains(':')) return false;
  if (provider != null) {
    return provider == 'google' || provider == 'google-ui-kit';
  }
  // Untagged: Google ids are long mixed-case base64url; Geoapify's are hex.
  return RegExp(r'^[A-Za-z0-9_-]{16,}$').hasMatch(id) &&
      !RegExp(r'^[0-9a-f]+$').hasMatch(id);
}

class PlacePhoto {
  const PlacePhoto({
    required this.name,
    required this.attribution,
    this.directUrl,
    this.sourceUrl = '',
    this.licenseUrl = '',
  });

  final String name;
  final String attribution;
  final String? directUrl;
  final String sourceUrl;
  final String licenseUrl;

  /// Served by `/api/place-photo`, which answers 503 once the daily Google
  /// budget is spent: show a placeholder image rather than an error.
  bool get viaGoogleProxy => directUrl == null;

  String get url =>
      directUrl ??
      Uri.parse('$workerBaseUrl/api/place-photo')
          .replace(queryParameters: {'name': name})
          .toString();

  factory PlacePhoto.fromJson(Map<String, dynamic> json) => PlacePhoto(
    name: json['name']?.toString() ?? '',
    attribution: json['attribution']?.toString() ?? '',
    directUrl: json['url']?.toString(),
    sourceUrl: json['sourceUrl']?.toString() ?? '',
    licenseUrl: json['licenseUrl']?.toString() ?? '',
  );
}

class PlaceReview {
  const PlaceReview({
    required this.author,
    required this.authorPhoto,
    required this.rating,
    required this.text,
    required this.relativeTime,
    required this.googleMapsUri,
  });
  final String author;
  final String? authorPhoto;
  final double? rating;
  final String text;
  final String relativeTime;
  final String? googleMapsUri;

  factory PlaceReview.fromJson(Map<String, dynamic> json) => PlaceReview(
    author: json['author']?.toString() ?? 'Google user',
    authorPhoto: json['authorPhoto']?.toString(),
    rating: (json['rating'] as num?)?.toDouble(),
    text: json['text']?.toString() ?? '',
    relativeTime: json['relativeTime']?.toString() ?? '',
    googleMapsUri: json['googleMapsUri']?.toString(),
  );
}

class PlaceDetails {
  const PlaceDetails({
    required this.placeId,
    required this.name,
    required this.address,
    required this.primaryType,
    required this.rating,
    required this.userRatingCount,
    required this.businessStatus,
    required this.priceLevel,
    required this.phone,
    required this.websiteUri,
    required this.googleMapsUri,
    required this.editorialSummary,
    required this.openingHours,
    required this.photos,
    required this.reviews,
  });

  final String placeId;
  final String name;
  final String address;
  final String primaryType;
  final double? rating;
  final int? userRatingCount;
  final String? businessStatus;
  final String? priceLevel;
  final String phone;
  final String websiteUri;
  final String googleMapsUri;
  final String editorialSummary;
  final List<String> openingHours;
  final List<PlacePhoto> photos;
  final List<PlaceReview> reviews;

  factory PlaceDetails.fromJson(Map<String, dynamic> json) {
    final photos = (json['photos'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PlacePhoto.fromJson)
        .where(
          (photo) =>
              photo.name.isNotEmpty || photo.directUrl?.isNotEmpty == true,
        )
        .toList(growable: false);
    final reviews = (json['reviews'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PlaceReview.fromJson)
        .toList(growable: false);
    return PlaceDetails(
      placeId: json['placeId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Selected place',
      address: json['address']?.toString() ?? '',
      primaryType: json['primaryType']?.toString() ?? '',
      rating: (json['rating'] as num?)?.toDouble(),
      userRatingCount: (json['userRatingCount'] as num?)?.round(),
      businessStatus: json['businessStatus']?.toString(),
      priceLevel: json['priceLevel']?.toString(),
      phone: json['phone']?.toString() ?? '',
      websiteUri: json['websiteUri']?.toString() ?? '',
      googleMapsUri: json['googleMapsUri']?.toString() ?? '',
      editorialSummary: json['editorialSummary']?.toString() ?? '',
      openingHours: (json['openingHours'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      photos: photos,
      reviews: reviews,
    );
  }
}

class PlaceDetailsRepository {
  PlaceDetailsRepository({http.Client? client, RateLimitGate? googleGate})
    : _client = client ?? http.Client(),
      _googleGate = googleGate ?? RateLimitGate();

  final http.Client _client;

  /// Holds Google lookups back after a 429 or `GOOGLE_BUDGET_EXHAUSTED`.
  final RateLimitGate _googleGate;

  Future<PlaceDetails> fetchIndependent(PlaceSummary place) async {
    final uri = Uri.parse('$workerBaseUrl/api/independent-place-details')
        .replace(
          queryParameters: {
            'id': place.reference?.id ?? '',
            'name': place.name,
            'address': place.address,
            'type': place.category,
            'at': '${place.location.longitude},${place.location.latitude}',
          },
        );
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 26));
    final decoded = decodeJsonResponse(
      response,
      unavailable: 'Place photos unavailable',
    );
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Place photos unavailable');
    }
    return PlaceDetails.fromJson(decoded);
  }

  /// Google place details. With [fallback], an id that is not a Google
  /// place id, a rate limit or an exhausted daily Google budget answers from
  /// `/api/independent-place-details` instead of failing.
  Future<PlaceDetails> fetch(
    String placeId, {
    String language = 'en',
    String? provider,
    PlaceSummary? fallback,
  }) async {
    if (!isGooglePlaceId(placeId, provider: provider)) {
      if (fallback != null) return fetchIndependent(fallback);
      throw ApiException('Place details unavailable');
    }
    final http.Response response;
    try {
      _googleGate.check();
      final uri = Uri.parse('$workerBaseUrl/api/place-details')
          .replace(queryParameters: {'placeId': placeId, 'lang': language});
      // Check the status before decoding: a Cloudflare 502 is an HTML page.
      response = await _client.get(uri).timeout(const Duration(seconds: 15));
      _googleGate.observe(response);
    } on RateLimitedException {
      if (fallback != null) return fetchIndependent(fallback);
      rethrow;
    }
    final decoded = decodeJsonResponse(
      response,
      unavailable: 'Place details unavailable',
    );
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Place details unavailable');
    }
    return PlaceDetails.fromJson(decoded);
  }

  void dispose() => _client.close();
}
