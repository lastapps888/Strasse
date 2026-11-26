import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:strasse/domain/domain.dart';

class GooglePlaceReview {
  const GooglePlaceReview({
    required this.rating,
    required this.text,
    required this.author,
    this.relativeTime,
    this.authorUri,
    this.authorPhotoUri,
    this.googleMapsUri,
    this.flagContentUri,
    this.visitDate,
    this.translated = false,
  });

  final double rating;
  final String text;
  final String author;
  final String? relativeTime;
  final String? authorUri;
  final String? authorPhotoUri;
  final String? googleMapsUri;
  final String? flagContentUri;
  final String? visitDate;
  final bool translated;
}

class GooglePlaceReviews {
  const GooglePlaceReviews({
    required this.placeName,
    required this.rating,
    required this.userRatingCount,
    required this.reviews,
    required this.googleMapsUri,
  });

  final String placeName;
  final double? rating;
  final int userRatingCount;
  final List<GooglePlaceReview> reviews;
  final String? googleMapsUri;
}

/// Avis Google Places (API New). Cette intégration est facultative et inactive sans clé configurée.
/// La recherche spatiale limite le risque d'associer les avis d'un établissement homonyme situé ailleurs.
class GooglePlacesReviewsClient {
  GooglePlacesReviewsClient(this.apiKey, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://places.googleapis.com/v1',
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 12),
              validateStatus: (status) => status != null && status < 400,
              headers: const {'Accept': 'application/json'},
            ));

  final String apiKey;
  final Dio _dio;

  Future<GooglePlaceReviews?> forPlace(Place place) async {
    if (apiKey.trim().isEmpty || place.name.trim().length < 3) return null;
    try {
      final search = await _dio.post<Map<String, dynamic>>(
        '/places:searchText',
        data: {
          'textQuery': place.name,
          'pageSize': 5,
          'languageCode': 'fr',
          'locationBias': {
            'circle': {
              'center': {
                'latitude': place.point.lat,
                'longitude': place.point.lon,
              },
              'radius': 180.0,
            },
          },
        },
        options: Options(headers: {
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask': 'places.id,places.displayName,places.location',
        }),
      );
      final candidates = search.data?['places'];
      if (candidates is! List) return null;

      Map<String, dynamic>? best;
      var bestDistance = double.infinity;
      final wanted = _fold(place.name);
      for (final raw in candidates) {
        if (raw is! Map) continue;
        final name = raw['displayName'] is Map ? (raw['displayName'] as Map)['text'] : null;
        final id = raw['id'];
        final location = raw['location'];
        if (name is! String || id is! String || location is! Map) continue;
        final lat = (location['latitude'] as num?)?.toDouble();
        final lon = (location['longitude'] as num?)?.toDouble();
        if (lat == null || lon == null) continue;
        final normalized = _fold(name);
        final matching = normalized == wanted ||
            normalized.contains(wanted) ||
            wanted.contains(normalized) ||
            _wordOverlap(wanted, normalized) >= 0.6;
        if (!matching) continue;
        final distance = _distanceMeters(place.point.lat, place.point.lon, lat, lon);
        if (distance <= 220 && distance < bestDistance) {
          bestDistance = distance;
          best = {'id': id, 'name': name};
        }
      }
      if (best == null) return null;

      final details = await _dio.get<Map<String, dynamic>>(
        '/places/${Uri.encodeComponent(best['id'] as String)}',
        options: Options(headers: {
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask': 'id,displayName,rating,userRatingCount,googleMapsUri,reviews.rating,reviews.text,reviews.originalText,reviews.authorAttribution,reviews.relativePublishTimeDescription,reviews.googleMapsUri,reviews.flagContentUri,reviews.visitDate',
        }),
      );
      final data = details.data;
      if (data == null) return null;
      final rawReviews = data['reviews'];
      final reviews = <GooglePlaceReview>[];
      if (rawReviews is List) {
        for (final raw in rawReviews.take(5)) {
          if (raw is! Map) continue;
          final author = raw['authorAttribution'];
          final text = raw['text'];
          final authorName = author is Map ? author['displayName'] : null;
          final reviewText = text is Map ? text['text'] : null;
          final originalText = raw['originalText'];
          final originalReviewText = originalText is Map ? originalText['text'] : null;
          final rating = (raw['rating'] as num?)?.toDouble();
          if (rating == null || reviewText is! String || reviewText.trim().isEmpty) continue;
          final visit = raw['visitDate'];
          final visitDate = visit is Map && visit['year'] is num && visit['month'] is num
              ? '${(visit['month'] as num).toInt().toString().padLeft(2, '0')}/${(visit['year'] as num).toInt()}'
              : null;
          reviews.add(GooglePlaceReview(
            rating: rating,
            text: reviewText.trim(),
            author: authorName is String && authorName.isNotEmpty ? authorName : 'Utilisateur Google',
            relativeTime: raw['relativePublishTimeDescription'] as String?,
            authorUri: author is Map ? author['uri'] as String? : null,
            authorPhotoUri: author is Map ? author['photoUri'] as String? : null,
            googleMapsUri: raw['googleMapsUri'] as String?,
            flagContentUri: raw['flagContentUri'] as String?,
            visitDate: visitDate,
            translated: originalReviewText is String &&
                originalReviewText.trim().isNotEmpty &&
                originalReviewText.trim() != reviewText.trim(),
          ));
        }
      }

      final displayName = data['displayName'];
      final returnedName = displayName is Map && displayName['text'] is String
          ? displayName['text'] as String
          : best['name'] as String;
      return GooglePlaceReviews(
        placeName: returnedName,
        rating: (data['rating'] as num?)?.toDouble(),
        userRatingCount: (data['userRatingCount'] as num?)?.toInt() ?? 0,
        reviews: reviews,
        googleMapsUri: data['googleMapsUri'] as String?,
      );
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _fold(String value) {
    return value
        .toLowerCase()
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('ç', 'c')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ô', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ü', 'u')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static double _wordOverlap(String a, String b) {
    final left = a.split(' ').where((word) => word.length > 2).toSet();
    final right = b.split(' ').where((word) => word.length > 2).toSet();
    if (left.isEmpty) return 0;
    return left.intersection(right).length / left.length;
  }

  static double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const radius = 6371000.0;
    final dLat = _radians(lat2 - lat1);
    final dLon = _radians(lon2 - lon1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_radians(lat1)) * math.cos(_radians(lat2)) * math.pow(math.sin(dLon / 2), 2);
    return 2 * radius * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}
