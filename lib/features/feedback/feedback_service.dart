import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:strasse/core/core.dart';

/// Envoi des retours au Worker Strasse : le destinataire et les identifiants du fournisseur e-mail restent côté serveur.
class FeedbackService {
  FeedbackService({Dio? dio, this.baseUrl = AppConfig.strasseServerUrl, String userAgent = ''})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              headers: {'Accept': 'application/json', if (userAgent.isNotEmpty) 'User-Agent': userAgent},
              validateStatus: (_) => true,
            ));

  final Dio _dio;
  final String baseUrl;

  static const int minLength = 10;
  static const int maxLength = 4000;

  /// Le Worker ne confirme que lorsque le fournisseur d'e-mail a accepté l'envoi.
  static bool responseAccepted(int? status, Object? data) {
    if (status == null || status < 200 || status >= 300 || data is! Map) return false;
    return data['success'] == true;
  }

  /// Sujet du message : « Feedback » suivi de la date d'envoi.
  static String subject(DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'Feedback ' + two(now.day) + '/' + two(now.month) + '/' + now.year.toString();
  }

  static String? validate(String text) {
    final value = text.trim();
    if (value.length < minLength) return 'Écrivez au moins ' + minLength.toString() + ' caractères.';
    if (value.length > maxLength) return 'Le message est trop long (maximum ' + maxLength.toString() + ' caractères).';
    return null;
  }

  /// Informations techniques facultatives, jointes seulement si la personne le demande.
  static String technicalInfo() => 'Strasse ' + AppConfig.version + ' · ' + defaultTargetPlatform.name;

  static String body(String text, {String? technical}) =>
      technical == null ? text.trim() : text.trim() + '\n\n---\n' + technical;

  Future<void> send(String text, {String? technical, String? replyTo}) async {
    final problem = validate(text);
    if (problem != null) throw Failure(FailureKind.client, problem, code: 'invalid_feedback');

    final endpoint = baseUrl.replaceFirst(RegExp(r'/+$'), '') + '/v1/feedback';
    final trimmedReply = replyTo?.trim() ?? '';
    try {
      final response = await _dio.post<Object>(
        endpoint,
        data: {
          'message': body(text, technical: technical),
          if (trimmedReply.isNotEmpty) 'replyTo': trimmedReply,
        },
        options: Options(contentType: Headers.jsonContentType),
      );
      if (!responseAccepted(response.statusCode, response.data)) {
        final data = response.data;
        final message = data is Map ? data['error'] is Map ? (data['error'] as Map)['message']?.toString() : data['message']?.toString() : null;
        throw Failure(
          FailureKind.server,
          message != null && message.isNotEmpty
              ? message
              : 'Le serveur Strasse n’a pas accepté le retour (HTTP ' + (response.statusCode ?? 0).toString() + ').',
          code: 'feedback_rejected',
        );
      }
    } on DioException catch (error) {
      throw Failure.fromDio(error);
    }
  }
}
