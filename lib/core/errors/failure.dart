import 'package:dio/dio.dart';

enum FailureKind { offline, timeout, server, client, unauthorized, notConfigured, permission, storage, unknown }

/// Erreur métier avec un message déjà prêt à être affiché à l'utilisateur, en français.
class Failure implements Exception {
  const Failure(this.kind, this.message, {this.code});

  final FailureKind kind;
  final String message;
  final String? code;

  bool get retryable =>
      kind == FailureKind.offline || kind == FailureKind.timeout || kind == FailureKind.server;

  factory Failure.notConfigured(String service, {String? hint}) => Failure(
        FailureKind.notConfigured,
        '$service n\'est pas configuré. ${hint ?? 'Renseignez le serveur dans Réglages > Services.'}',
        code: 'not_configured',
      );

  factory Failure.offline() => const Failure(
        FailureKind.offline,
        'Connexion impossible. Vérifiez votre réseau puis réessayez.',
        code: 'offline',
      );

  factory Failure.unknown([Object? error]) => Failure(
        FailureKind.unknown,
        'Une erreur inattendue est survenue. Réessayez dans un instant.',
        code: error?.runtimeType.toString(),
      );

  /// Convertit une erreur Dio (backend Strasse, Valhalla, Nominatim, TomTom…) en message clair.
  factory Failure.fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const Failure(FailureKind.timeout, 'Le serveur met trop de temps à répondre. Réessayez.', code: 'timeout');
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        return Failure.offline();
      case DioExceptionType.cancel:
        return const Failure(FailureKind.unknown, 'Opération annulée.', code: 'cancelled');
      case DioExceptionType.badCertificate:
        return const Failure(FailureKind.client, 'La connexion sécurisée au serveur a échoué (certificat invalide).', code: 'bad_certificate');
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        break;
    }
    final status = e.response?.statusCode;
    final data = e.response?.data;
    String? serverMessage;
    String? code;
    if (data is Map) {
      final err = data['error'];
      if (err is Map) {
        serverMessage = err['message']?.toString();
        code = err['code']?.toString();
      } else if (err is String) {
        serverMessage = err; // Valhalla : {"error": "...", "error_code": 171}
        code = data['error_code']?.toString();
      }
    }
    if (status == 401) {
      return Failure(FailureKind.unauthorized, serverMessage ?? 'Session expirée. Veuillez vous reconnecter.', code: code ?? 'unauthorized');
    }
    if (status == 429) {
      return Failure(FailureKind.client, serverMessage ?? 'Trop de requêtes. Réessayez dans quelques instants.', code: code ?? 'rate_limited');
    }
    if (status != null && status >= 500) {
      return Failure(FailureKind.server, 'Le serveur rencontre un problème (${status}). Réessayez plus tard.', code: code ?? 'server_error');
    }
    if (status != null && status >= 400) {
      return Failure(FailureKind.client, serverMessage ?? 'Requête refusée par le serveur ($status).', code: code);
    }
    return Failure.offline();
  }

  @override
  String toString() => 'Failure($kind, $message)';
}

/// Transforme n'importe quelle exception en [Failure].
Failure toFailure(Object error) {
  if (error is Failure) return error;
  if (error is DioException) return Failure.fromDio(error);
  return Failure.unknown(error);
}
