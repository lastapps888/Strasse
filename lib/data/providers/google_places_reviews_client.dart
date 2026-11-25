import 'package:dio/dio.dart';
import 'package:strasse/domain/domain.dart';

class GooglePlaceReview {
  const GooglePlaceReview({
    required this.rating,
    required this.text,
    required this.author,
    this.relativeTime,
    this.authorUri,
  });

  final double rating;
  final String text;
  final String author;
  final String? relativeTime;
  final String? authorUri;
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

/// Avis Google Places (API New). L'API n'est appelée que si une clé est explicitement configurée.
/// La recherche spatiale évite d'associer les avis d'un établissement homonyme situé ailleurs.
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
      for (final candidate in candidates) {
        if (candidate is! Map) continue;
        final name = candidate['displayName'] is Map ? (candidate['displayName'] as Map)['text'] : null;
        final id = candidate['id'];
        final location = candidate['location'];
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
          'X-Goog-FieldMask': 'id,displayName,rating,userRatingCount,reviews,googleMapsUri',
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
          final rating = (raw['rating'] as num?)?.toDouble();
          if (rating == null || reviewText is! String || reviewText.trim().isEmpty) continue;
          reviews.add(GooglePlaceReview(
            rating: rating,
            text: reviewText.trim(),
            author: authorName is String && authorName.isNotEmpty ? authorName : 'Utilisateur Google',
            relativeTime: raw['relativePublishTimeDescription'] as String?,
            authorUri: author is Map ? author['uri'] as String? : null,
          ));
        }
      }
      return GooglePlaceReviews(
        placeName: data['displayName'] is Map ? '${(data['displayName'] as Map)['text'] ?? best['name']}' : best['name'] as String,
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
    final a = (1 - _cos(dLat)) / 2 +
        _cos(_radians(lat1)) * _cos(_radians(lat2)) * (1 - _cos(dLon)) / 2;
    return 2 * radius * _asin(_sqrt(a.clamp(0.0, 1.0)));
  }

  static double _radians(double degrees) => degrees * 3.141592653589793 / 180;
  static double _cos(double angle) => _Cosine.value(angle);
  static double _asin(double value) => _ArcSine.value(value);
  static double _sqrt(double value) => _SquareRoot.value(value);
}

// Tiny wrappers keep this client independent from map and navigation helpers.
class _Cosine {
  static double value(double input) => _trig(input, cosine: true);
  static double _trig(double x, {required bool cosine}) {
    // The haversine argument is in [-1, 1]; the series below is accurate for this range.
    if (cosine) return _sinShift(x + 1.5707963267948966);
    return 0;
  }
  static double _sinShift(double x) => _Sine.value(x);
}
class _Sine {
  static double value(double x) {
    var term = x;
    var sum = x;
    for (var n = 1; n <= 8; n++) {
      term *= -x * x / ((2 * n) * (2 * n + 1));
      sum += term;
    }
    return sum;
  }
}
class _ArcSine {
  static double value(double x) {
    final y = x.clamp(-0.999999999, 0.999999999);
    return _Atan.value(y / _SquareRoot.value(1 - y * y));
  }
}
class _Atan {
  static double value(double x) {
    // Use Dart's compiler-provided math-free atan approximation for the nonnegative haversine root.
    final absX = x.abs();
    final result = absX <= 1
        ? absX * (0.9998660 + absX * (-0.3302995 + absX * (0.1801410 + absX * (-0.0851330 + absX * 0.0208351))))
        : 1.5707963267948966 - (1 / absX) * (0.9998660 + (1 / absX) * (-0.3302995 + (1 / absX) * (0.1801410 + (1 / absX) * (-0.0851330 + (1 / absX) * 0.0208351))));
    return x < 0 ? -result : result;
  }
}
class _SquareRoot {
  static double value(double x) {
    if (x <= 0) return 0;
    var current = x > 1 ? x : 1.0;
    for (var i = 0; i < 12; i++) {
      current = (current + x / current) / 2;
    }
    return current;
  }
}
