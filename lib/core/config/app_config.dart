/// Configuration centralisée de Strasse, lue à la compilation via `--dart-define`.
///
/// Aucune clé privée ici : une application mobile est publique. Les adresses de services peuvent
/// aussi être modifiées dans l'application (Réglages > Services), ce qui remplace ces valeurs.
class AppConfig {
  const AppConfig({
    required this.env,
    required this.apiUrl,
    required this.tilesUrl,
    required this.tilesAttribution,
    required this.glyphsUrl,
    required this.mapFont,
    required this.valhallaUrl,
    required this.geocoderUrl,
    required this.otpUrl,
    this.overpassUrl = '',
    this.supabaseUrl = '',
    this.supabaseAnonKey = '',
    this.openTripMapKey = '',
    this.spotifyClientId = '',
    this.youtubeIosClientId = '',
    this.youtubeServerClientId = '',
    this.googlePlacesApiKey = '',
    this.contact = '',
  });

  static const String defaultSupabaseUrl = 'https://msgaoprkocgbsirbjaab.supabase.co';
  static const String defaultSupabasePublishableKey = 'sb_publishable_3TXETm0ckp57A6TQfyJ-eg_dD_EkyOd';

  static const AppConfig fromEnvironment = AppConfig(
    env: String.fromEnvironment('STRASSE_ENV', defaultValue: 'dev'),
    apiUrl: String.fromEnvironment('STRASSE_API_URL'),
    tilesUrl: String.fromEnvironment('STRASSE_TILES_URL'),
    tilesAttribution: String.fromEnvironment('STRASSE_TILES_ATTRIBUTION'),
    glyphsUrl: String.fromEnvironment('STRASSE_GLYPHS_URL'),
    mapFont: String.fromEnvironment('STRASSE_MAP_FONT', defaultValue: 'Noto Sans Regular'),
    valhallaUrl: String.fromEnvironment('STRASSE_VALHALLA_URL'),
    geocoderUrl: String.fromEnvironment('STRASSE_GEOCODER_URL'),
    otpUrl: String.fromEnvironment('STRASSE_OTP_URL'),
    overpassUrl: String.fromEnvironment('STRASSE_OVERPASS_URL'),
    supabaseUrl: String.fromEnvironment('STRASSE_SUPABASE_URL', defaultValue: defaultSupabaseUrl),
    supabaseAnonKey: String.fromEnvironment('STRASSE_SUPABASE_ANON_KEY', defaultValue: defaultSupabasePublishableKey),
    openTripMapKey: String.fromEnvironment('STRASSE_OPENTRIPMAP_KEY'),
    spotifyClientId: String.fromEnvironment('STRASSE_SPOTIFY_CLIENT_ID'),
    youtubeIosClientId: String.fromEnvironment('STRASSE_YOUTUBE_IOS_CLIENT_ID'),
    youtubeServerClientId: String.fromEnvironment('STRASSE_YOUTUBE_SERVER_CLIENT_ID'),
    googlePlacesApiKey: String.fromEnvironment('STRASSE_GOOGLE_PLACES_API_KEY'),
    contact: String.fromEnvironment('STRASSE_CONTACT'),
  );

  final String env;
  final String apiUrl;
  final String tilesUrl;
  final String tilesAttribution;
  final String glyphsUrl;
  final String mapFont;
  final String valhallaUrl;
  final String geocoderUrl;
  final String otpUrl;

  /// Point d'accès Overpass (…/api/interpreter) utilisé pour préparer les itinéraires hors connexion.
  final String overpassUrl;

  /// Projet Supabase Strasse : URL et clé publique anon/publishable. Une clé secrète ne doit jamais être intégrée au client.
  final String supabaseUrl;
  final String supabaseAnonKey;

  /// Clé gratuite OpenTripMap, identifiant client Spotify (PKCE, public).
  final String openTripMapKey;
  final String spotifyClientId;
  final String youtubeIosClientId;
  final String youtubeServerClientId;
  final String googlePlacesApiKey;

  /// Contact (adresse e-mail ou site) inclus dans le User-Agent, exigé par les politiques d'usage d'OSM.
  final String contact;

  /// User-Agent identifiable pour les services publics (Nominatim, Overpass…).
  String get userAgent => contact.isEmpty ? 'Strasse/$version (application de navigation libre)' : 'Strasse/$version ($contact)';

  bool get isProduction => env == 'prod';
  bool get isTest => env == 'test';
  bool get isDev => env == 'dev';

  static const String appName = 'Strasse';
  static const String version = '1.0.0';
  static const String osmAttribution = '© Contributeurs OpenStreetMap';
  static const String osmCopyrightUrl = 'https://www.openstreetmap.org/copyright';
  /// Serveur Strasse hébergé (Cloudflare Worker, voir server/cloudflare). À remplacer par l'adresse de votre déploiement.
  static const String strasseServerUrl = 'https://strasse-server.lastapps888.workers.dev';
  static const String releasesUrl = 'https://github.com/lastapps888/Strasse/releases';
  static const String repoUrl = 'https://github.com/lastapps888/Strasse';

  /// Destinataire des retours d'utilisateurs (adresse publique, aucun secret).
}
