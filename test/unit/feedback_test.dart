import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/features/feedback/feedback_service.dart';

void main() {
  test('le sujet contient Feedback et la date d’envoi', () {
    expect(FeedbackService.subject(DateTime(2026, 11, 8)), 'Feedback 08/11/2026');
    expect(FeedbackService.subject(DateTime(2027, 1, 31)), 'Feedback 31/01/2027');
  });

  test('un succès serveur explicite est requis avant de confirmer l’envoi', () {
    expect(FeedbackService.responseAccepted(200, {'success': true}), isTrue);
    expect(FeedbackService.responseAccepted(201, {'success': true}), isTrue);
    expect(FeedbackService.responseAccepted(200, {'success': 'true'}), isFalse);
    expect(FeedbackService.responseAccepted(200, {'message': 'accepted'}), isFalse);
    expect(FeedbackService.responseAccepted(503, {'success': true}), isFalse);
    expect(FeedbackService.responseAccepted(200, 'OK'), isFalse);
  });

  test('validation du texte', () {
    expect(FeedbackService.validate('court'), isNotNull);
    expect(FeedbackService.validate('Un message assez long'), isNull);
    expect(FeedbackService.validate(List<String>.filled(5000, 'x').join()), isNotNull);
  });

  test('le corps ne contient que le texte et les informations facultatives choisies', () {
    expect(FeedbackService.body(' Bonjour '), 'Bonjour');
    expect(FeedbackService.body('Bonjour', technical: 'Strasse 1.0.0'), 'Bonjour\n\n---\nStrasse 1.0.0');
  });
}
