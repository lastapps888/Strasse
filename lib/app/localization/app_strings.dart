import 'package:flutter/material.dart';
import 'package:strasse/core/core.dart';

/// Libellés communs. Le français est la langue de référence ; [tr] les traduit dans la langue choisie.
class AppStrings {
  const AppStrings(this.locale);
  final Locale locale;

  static final supported = [for (final l in AppLanguage.values) l.locale];

  static AppStrings of(BuildContext context) => AppStrings(Localizations.localeOf(context));

  String get tabHome => tr('Accueil');
  String get tabMap => tr('Carte');
  String get tabSaved => tr('Enregistrés');
  String get tabMusic => tr('Musique');
  String get tabSettings => tr('Réglages');
  String get search => tr('Rechercher un lieu ou une adresse');
  String get retry => tr('Réessayer');
  String get cancel => tr('Annuler');
  String get ok => 'OK';
  String get delete => tr('Supprimer');
  String get save => tr('Enregistrer');
  String get start => tr('Démarrer');
}
