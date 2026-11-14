import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/features/feedback/feedback_service.dart';

void main() {
  test('le titre est « Feedback » suivi de la date du jour d\'envoi', () {
    expect(FeedbackService.subject(DateTime(2026, 11, 8)), 'Feedback 08/11/2026');
    expect(FeedbackService.subject(DateTime(2027, 1, 31)), 'Feedback 31/01/2027');
  });

  test('validation du texte', () {
    expect(FeedbackService.validate('court'), isNotNull);
    expect(FeedbackService.validate('Un message assez long'), isNull);
    expect(FeedbackService.validate('x' * 5000), isNotNull);
  });

  test('mailto prérempli vers l\'adresse du projet', () {
    final u = FeedbackService().mailto('Bonjour, ceci est un test', now: DateTime(2026, 11, 8));
    expect(u.scheme, 'mailto');
    expect(u.path, 'srohsed.barjo.projet@gmail.com');
    expect(u.query, contains('Feedback%2008%2F11%2F2026'));
  });
}
