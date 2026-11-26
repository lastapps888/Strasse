import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/core/i18n/app_language.dart';
import 'package:strasse/core/i18n/translator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('les six dictionnaires ajoutés sont chargés depuis les ressources de l’application', () async {
    const languages = [
      AppLanguage.vi,
      AppLanguage.hi,
      AppLanguage.bn,
      AppLanguage.ur,
      AppLanguage.id,
      AppLanguage.tr,
    ];

    for (final language in languages) {
      await Translator.load(language);
      expect(Translator.language, language, reason: 'Le dictionnaire ${language.code} doit être chargé, sans repli silencieux vers le français.');
      expect(Translator.translate('Détails'), isNot('Détails'), reason: 'La clé « Détails » doit être traduite en ${language.code}.');
      expect(
        Translator.translate('Lignes, arrêts et horaires ; zoomez pour les voir'),
        isNot('Lignes, arrêts et horaires ; zoomez pour les voir'),
        reason: 'Les couches de transport doivent être traduites en ${language.code}.',
      );
    }

    await Translator.load(AppLanguage.fr);
  });

  test('l’ourdou est déclaré de droite à gauche', () {
    expect(AppLanguage.ur.rtl, isTrue);
    expect(AppLanguage.ur.locale.languageCode, 'ur');
  });
}
