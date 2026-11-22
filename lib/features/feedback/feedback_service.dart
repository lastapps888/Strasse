import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:strasse/core/core.dart';

/// Envoi des retours d'utilisateurs : un texte écrit par la personne, relayé par e-mail vers l'adresse du projet.
class FeedbackService {
  FeedbackService({Dio? dio, this.baseUrl = 'https://formsubmit.co', this.recipient = AppConfig.feedbackEmail, String userAgent = ''})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              headers: {'Accept': 'application/json', if (userAgent.isNotEmpty) 'User-Agent': userAgent},
              validateStatus: (_) => true,
            ));

  final Dio _dio;
  final String baseUrl;
  final String recipient;

  static const int minLength = 10;
  static const int maxLength = 4000;

  /// FormSubmit peut répondre HTTP 200 même lorsqu'il refuse la demande.
  /// La confirmation n'est autorisée qu'avec son indicateur JSON de réussite explicite.
  static bool responseAccepted(int? status, Object? data) {
    if (status == null || status < 200 || status >= 300 || data is! Map) return false;
    final success = data['success'];
    return success == true || success == 'true';
  }

  /// « Feedback 08/11/2026 » : le titre est toujours le mot Feedback suivi de la date d'envoi.
  static String subject(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Feedback ${two(now.day)}/${two(now.month)}/${now.year}';
  }

  /// Message d'erreur si le texte n'est pas envoyable, sinon null.
  static String? validate(String text) {
    final t = text.trim();
    if (t.length < minLength) return 'Écrivez au moins $minLength caractères.';
    if (t.length > maxLength) return 'Le message est trop long (maximum $maxLength caractères).';
    return null;
  }

  /// Informations techniques facultatives, jointes seulement si la personne le demande.
  static String technicalInfo() => 'Strasse ${AppConfig.version} · ${defaultTargetPlatform.name}';

  /// Contenu du message tel qu'envoyé.
  static String body(String text, {String? technical}) => technical == null ? text.trim() : '${text.trim()}\n\n---\n$technical';

  /// Envoi automatique via FormSubmit (API AJAX). Lève une [Failure] lisible en cas d'échec.
  Future<void> send(String text, {String? technical, String? replyTo, DateTime? now}) async {
    final problem = validate(text);
    if (problem != null) throw Failure(FailureKind.client, problem, code: 'invalid_feedback');
    final date = now ?? DateTime.now();
    try {
      final r = await _dio.post<Object>(
        '$baseUrl/ajax/$recipient',
        data: {
          '_subject': subject(date),
          '_template': 'basic',
          '_captcha': 'false',
          'message': body(text, technical: technical),
          if (replyTo != null && replyTo.trim().isNotEmpty) 'email': replyTo.trim(),
        },
        options: Options(contentType: Headers.jsonContentType),
      );
      final status = r.statusCode ?? 0;
      final data = r.data;
      if (!responseAccepted(status, data)) {
        final msg = data is Map ? data['message']?.toString() : null;
        throw Failure(
          FailureKind.server,
          msg != null && msg.isNotEmpty
              ? 'Le service d\'envoi a refusé le message : $msg'
              : 'Le service d\'envoi a répondu $status. Si c\'est la première utilisation, le destinataire doit d\'abord confirmer l\'e-mail d\'activation de FormSubmit.',
          code: 'feedback_rejected',
        );
      }
    } on DioException catch (e) {
      throw Failure.fromDio(e);
    }
  }

  /// Lien `mailto:` prérempli (repli, ou fournisseur « application e-mail »).
  Uri mailto(String text, {String? technical, DateTime? now}) => Uri(
        scheme: 'mailto',
        path: recipient,
        query: 'subject=${Uri.encodeComponent(subject(now ?? DateTime.now()))}&body=${Uri.encodeComponent(body(text, technical: technical))}',
      );
}
