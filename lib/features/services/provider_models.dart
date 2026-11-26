import 'package:flutter/foundation.dart';

/// Catégories de services externes gérées dans Réglages > Services.
enum ServiceCategory {
  tiles('tiles', 'Cartographie et tuiles vectorielles', 'Fond de carte OpenStreetMap (MapLibre).'),
  glyphs('glyphs', 'Polices de la carte (glyphes)', 'Polices des libellés de la carte.'),
  geocoding('geocoding', 'Recherche d\'adresses', 'Recherche de lieux et suggestions pendant la saisie.'),
  reverse('reverse', 'Géocodage inverse', 'Adresse d\'un point de la carte.'),
  routing('routing', 'Calcul d\'itinéraires', 'Voiture, marche, vélo, camion, moto.'),
  roadData('roadData', 'Données routières (Overpass)', 'Réseau routier hors connexion, points d\'intérêt.'),
  transit('transit', 'Transports en commun', 'Itinéraires, arrêts et horaires (Transitous/MOTIS ou OpenTripPlanner).'),
  tourism('tourism', 'Données touristiques', 'Sites et attractions à visiter.'),
  hotels('hotels', 'Hôtels', 'Découverte des hébergements.'),
  restaurants('restaurants', 'Restaurants', 'Découverte des restaurants.'),
  booking('booking', 'Réservations', 'Accès à la réservation dans l\'application.'),
  googlePlacesReviews('googlePlacesReviews', 'Notes et avis des lieux', 'Notes et avis publics Google Maps pour les lieux qui correspondent.'),
  traffic('traffic', 'Trafic', 'Incidents et perturbations routières.'),
  reports('reports', 'Signalements', 'Signalements communautaires partagés.'),
  feedback('feedback', 'Retours (feedback)', 'Envoi de vos commentaires à l\'équipe du projet.'),
  account('account', 'Compte et synchronisation', 'Compte facultatif et synchronisation entre appareils.'),
  spotify('spotify', 'Spotify', 'Contrôle de la lecture Spotify.'),
  appleMusic('appleMusic', 'Apple Music', 'Lecture et recherche Apple Music (iOS).'),
  deezer('deezer', 'Deezer', 'Recherche et extraits Deezer.'),
  youtubeMusic('youtubeMusic', 'YouTube Music', 'Connexion Google et playlists YouTube Music.'),
  localMusic('localMusic', 'Musique locale', 'Fichiers audio de l\'appareil.');

  const ServiceCategory(this.id, this.label, this.description);
  final String id;
  final String label;
  final String description;

  static ServiceCategory? byId(String? id) {
    for (final c in values) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// Nature d'un fournisseur.
enum ProviderKind {
  /// Serveur HTTP(S) joignable par une adresse de base.
  url,

  /// Service nécessitant des identifiants (clé, identifiant client, projet).
  credentials,

  /// Fonction native du système, aucune adresse nécessaire.
  native,

  /// Liens ouverts dans le navigateur intégré, sans API.
  link,
}

/// Champ d'identifiant à renseigner pour un fournisseur de type [ProviderKind.credentials].
@immutable
class ProviderField {
  const ProviderField(this.key, this.label, {this.secret = false, this.hint = '', this.isUrl = false});
  final String key;
  final String label;
  final bool secret;
  final String hint;
  final bool isUrl;
}

@immutable
class ServiceProvider {
  const ServiceProvider({
    required this.id,
    required this.category,
    required this.name,
    required this.description,
    this.kind = ProviderKind.url,
    this.baseUrl = '',
    this.adapter = '',
    this.recommended = false,
    this.custom = false,
    this.license = '',
    this.termsUrl = '',
    this.docUrl = '',
    this.limits = '',
    this.features = const [],
    this.fields = const [],
    this.fallbackGroup = '',
    this.needsSetup = false,
  });

  final String id;
  final ServiceCategory category;
  final String name;
  final String description;
  final ProviderKind kind;

  /// Adresse de base (HTTPS) ou modèle d'adresse (glyphes).
  final String baseUrl;

  /// Format d'API : valhalla, nominatim, photon, overpass, otp, tilejson, styleurl, glyphs, strasse-api, supabase, spotify, deezer, opentripmap…
  final String adapter;
  final bool recommended;
  final bool custom;
  final String license;
  final String termsUrl;
  final String docUrl;
  final String limits;
  final List<String> features;
  final List<ProviderField> fields;

  /// Les fournisseurs d'un même groupe sont interchangeables : le suivant prend le relais si le premier est en panne.
  final String fallbackGroup;

  /// Vrai si l'adresse ou les identifiants doivent être fournis (aucune instance publique universelle).
  final bool needsSetup;

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category.id,
        'name': name,
        'description': description,
        'baseUrl': baseUrl,
        'adapter': adapter,
      };

  static ServiceProvider? fromJson(Object? j) {
    if (j is! Map) return null;
    final cat = ServiceCategory.byId(j['category'] as String?);
    final id = j['id'], name = j['name'], url = j['baseUrl'];
    if (cat == null || id is! String || name is! String || url is! String) return null;
    return ServiceProvider(
      id: id,
      category: cat,
      name: name,
      description: j['description'] is String ? j['description'] as String : '',
      baseUrl: url,
      adapter: j['adapter'] is String ? j['adapter'] as String : '',
      custom: true,
    );
  }
}

/// Résultat d'un test de fournisseur.
@immutable
class ProviderTestResult {
  const ProviderTestResult({required this.ok, required this.message, this.latency});
  final bool ok;
  final String message;
  final Duration? latency;
}

/// Valide une adresse saisie par l'utilisateur : HTTPS obligatoire, hôte renseigné, pas d'identifiants dans l'adresse.
/// Retourne un message d'erreur, ou null si valide. [template] autorise les marqueurs {z}/{x}/{y}/{fontstack}/{range}.
String? validateProviderUrl(String input, {bool template = false}) {
  final v = input.trim();
  if (v.isEmpty) return 'Saisissez une adresse.';
  final probe = template ? v.replaceAll(RegExp(r'\{[a-z]+\}'), 'x') : v;
  final uri = Uri.tryParse(probe);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return 'Adresse invalide.';
  if (uri.scheme != 'https') return 'L\'adresse doit commencer par https://.';
  if (uri.userInfo.isNotEmpty) return 'N\'incluez ni identifiant ni mot de passe dans l\'adresse.';
  if (uri.host == 'localhost' || !uri.host.contains('.')) return 'Nom de domaine complet requis (ex. exemple.org).';
  return null;
}
