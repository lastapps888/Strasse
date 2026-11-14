import 'dart:ui' show Locale;

/// Langues de l'interface. Le français est la langue de référence du code : tous les textes y sont écrits en français
/// et traduits à l'affichage depuis `assets/i18n/<code>.json`.
enum AppLanguage {
  fr('fr', 'Français', 'fr-FR', 'fr-FR'),
  en('en', 'English', 'en-US', 'en-US'),
  de('de', 'Deutsch', 'de-DE', 'de-DE'),
  ru('ru', 'Русский', 'ru-RU', 'ru-RU'),
  ar('ar', 'العربية', 'ar-SA', 'en-US', rtl: true),
  zh('zh', '中文', 'zh-CN', 'en-US'),
  es('es', 'Español', 'es-ES', 'es-ES'),
  it('it', 'Italiano', 'it-IT', 'it-IT'),
  pt('pt', 'Português', 'pt-PT', 'pt-PT'),
  pl('pl', 'Polski', 'pl-PL', 'pl-PL'),
  nl('nl', 'Nederlands', 'nl-NL', 'nl-NL'),
  ja('ja', '日本語', 'ja-JP', 'ja-JP');

  const AppLanguage(this.code, this.nativeName, this.ttsTag, this.routingTag, {this.rtl = false});

  final String code;

  /// Nom de la langue dans cette langue (toujours affiché ainsi, pour pouvoir la retrouver).
  final String nativeName;

  /// Langue de la synthèse vocale du système.
  final String ttsTag;

  /// Langue des instructions renvoyées par Valhalla. Valhalla ne propose ni l'arabe ni le chinois : l'anglais est utilisé.
  final String routingTag;
  final bool rtl;

  Locale get locale => Locale(code);

  static AppLanguage fromCode(String? code) {
    for (final l in values) {
      if (l.code == code) return l;
    }
    return AppLanguage.fr;
  }

  /// Langue de l'appareil si elle fait partie des douze, sinon le français.
  static AppLanguage fromDevice(String? deviceCode) => fromCode(deviceCode);

  /// Convertit le réglage enregistré : vide = suivre l'appareil.
  static AppLanguage resolve(String setting, String? deviceCode) => setting.isEmpty ? fromDevice(deviceCode) : fromCode(setting);
}
