import 'package:flutter/material.dart';

/// Textes de navigation et libellés communs. Le français est la langue de référence de l'application ;
/// l'anglais ne couvre que ces libellés communs (le reste de l'interface est en français).
class AppStrings {
  const AppStrings(this.locale);
  final Locale locale;

  static const supported = [Locale('fr'), Locale('en')];

  static AppStrings of(BuildContext context) => AppStrings(Localizations.localeOf(context));

  bool get _en => locale.languageCode == 'en';

  String get tabHome => _en ? 'Home' : 'Accueil';
  String get tabMap => _en ? 'Map' : 'Carte';
  String get tabTrips => _en ? 'Trips' : 'Trajets';
  String get tabFavorites => _en ? 'Favorites' : 'Favoris';
  String get tabSettings => _en ? 'Settings' : 'Réglages';
  String get search => _en ? 'Search a place or address' : 'Rechercher un lieu ou une adresse';
  String get retry => _en ? 'Retry' : 'Réessayer';
  String get cancel => _en ? 'Cancel' : 'Annuler';
  String get ok => 'OK';
  String get delete => _en ? 'Delete' : 'Supprimer';
  String get save => _en ? 'Save' : 'Enregistrer';
  String get start => _en ? 'Start' : 'Démarrer';
}
