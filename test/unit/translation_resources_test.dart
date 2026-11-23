import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/core/i18n/app_language.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const targetCodes = ['vi', 'hi', 'bn', 'ur', 'id', 'tr'];

  group('Beta 6 translation resources', () {
    late Set<String> expectedKeys;

    setUpAll(() async {
      final raw = await rootBundle.loadString('assets/i18n/vi.json');
      expectedKeys = (jsonDecode(raw) as Map<String, dynamic>).keys.toSet();
    });

    for (final code in targetCodes) {
      test('$code contains the complete shared key set and valid placeholders', () async {
        final raw = await rootBundle.loadString('assets/i18n/$code.json');
        final dictionary = jsonDecode(raw) as Map<String, dynamic>;
        final keys = dictionary.keys.toSet();

        expect(keys, expectedKeys, reason: 'All six Beta 6 dictionaries must stay in sync.');
        for (final entry in dictionary.entries) {
          expect(entry.value, isA<String>(), reason: '$code:${entry.key}');
          expect((entry.value as String).trim(), isNotEmpty, reason: '$code:${entry.key}');

          final sourcePlaceholders = _placeholders(entry.key).toSet();
          final translatedPlaceholders = _placeholders(entry.value as String);
          expect(
            translatedPlaceholders.every(sourcePlaceholders.contains),
            isTrue,
            reason: '$code:${entry.key} must not introduce placeholders absent from its source phrase.',
          );
          if (sourcePlaceholders.contains('{0}')) {
            expect(
              translatedPlaceholders,
              contains('{0}'),
              reason: '$code:${entry.key} must retain the main inserted value.',
            );
          }
        }
      });
    }

    test('Urdu uses right-to-left layout while the other target languages remain left-to-right', () {
      expect(AppLanguage.ur.rtl, isTrue);
      for (final code in const ['vi', 'hi', 'bn', 'id', 'tr']) {
        expect(AppLanguage.fromCode(code).rtl, isFalse, reason: code);
      }
    });
  });
}

List<String> _placeholders(String text) =>
    RegExp(r'\{\d+\}').allMatches(text).map((match) => match.group(0)!).toList();
