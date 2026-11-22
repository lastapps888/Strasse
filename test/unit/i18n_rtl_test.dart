import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/app/localization/app_strings.dart';
import 'package:strasse/core/i18n/app_language.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('les six langues Beta 6 font partie des langues prises en charge', () {
    for (final language in [
      AppLanguage.vi,
      AppLanguage.hi,
      AppLanguage.bn,
      AppLanguage.ur,
      AppLanguage.id,
      AppLanguage.tr,
    ]) {
      expect(AppStrings.supported, contains(language.locale));
    }
  });

  test('arabe et ourdou sont déclarés RTL', () {
    expect(AppLanguage.ar.rtl, isTrue);
    expect(AppLanguage.ur.rtl, isTrue);
    expect(AppLanguage.vi.rtl, isFalse);
    expect(AppLanguage.hi.rtl, isFalse);
    expect(AppLanguage.bn.rtl, isFalse);
    expect(AppLanguage.id.rtl, isFalse);
    expect(AppLanguage.tr.rtl, isFalse);
  });

  for (final locale in [const Locale('ar'), const Locale('ur')]) {
    testWidgets('MaterialApp configure la direction RTL pour ' + locale.languageCode, (tester) async {
      const probeKey = Key('rtl-probe');
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: [locale],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          key: probeKey,
          builder: (_) => const SizedBox.shrink(),
        ),
      ));

      final context = tester.element(find.byKey(probeKey));
      expect(Directionality.of(context), TextDirection.rtl);
    });
  }
}
