import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/core/i18n/app_language.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Application translation resources', () {
    late Map<String, dynamic> reference;

    setUpAll(() async {
      reference = jsonDecode(await rootBundle.loadString('assets/i18n/en.json')) as Map<String, dynamic>;
    });

    for (final language in AppLanguage.values.where((language) => language != AppLanguage.fr)) {
      test('${language.code} has the complete translation key set', () async {
        final raw = await rootBundle.loadString('assets/i18n/${language.code}.json');
        final dictionary = jsonDecode(raw) as Map<String, dynamic>;

        expect(dictionary.keys.toSet(), reference.keys.toSet(),
            reason: 'The ${language.code} dictionary must contain every application translation key.');
        for (final entry in dictionary.entries) {
          expect(entry.value, isA<String>(), reason: '${language.code}:${entry.key}');
          expect((entry.value as String).trim(), isNotEmpty, reason: '${language.code}:${entry.key}');
          expect(
            _placeholders(entry.value as String),
            _placeholders(entry.key),
            reason: 'The placeholders in ${language.code}:${entry.key} must match the source phrase.',
          );
        }
      });
    }

    test('Arabic and Urdu are configured as right-to-left languages', () {
      expect(AppLanguage.ar.rtl, isTrue);
      expect(AppLanguage.ur.rtl, isTrue);
      expect(AppLanguage.fr.rtl, isFalse);
      expect(AppLanguage.en.rtl, isFalse);
    });
  });
}

List<String> _placeholders(String text) {
  final values = RegExp(r'\\{\\d+\\}').allMatches(text).map((match) => match.group(0)!).toList()..sort();
  return values;
}
