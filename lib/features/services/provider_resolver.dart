import 'package:strasse/core/core.dart';
import 'package:strasse/features/services/provider_catalog.dart';
import 'package:strasse/features/services/provider_models.dart';
import 'package:strasse/features/settings/settings_model.dart';

/// Identifiants saisis par l'utilisateur, par fournisseur : `identifiantFournisseur.champ` → valeur.
typedef Credentials = Map<String, String>;

/// Résout, pour chaque catégorie, le fournisseur actif et la liste de ses remplaçants.
///
/// Ordre de priorité : choix explicite de l'utilisateur > valeur de compilation (`--dart-define`) > fournisseur recommandé.
class ProviderResolver {
  const ProviderResolver(this.settings, this.config, [this.credentials = const {}]);

  final AppSettings settings;
  final AppConfig config;
  final Credentials credentials;

  /// Tous les fournisseurs d'une catégorie : intégrés, puis personnalisés.
  List<ServiceProvider> all(ServiceCategory c) => [
        ...ProviderCatalog.of(c),
        for (final p in settings.customProviders)
          if (p.category == c) p,
      ];

  ServiceProvider? _byId(ServiceCategory c, String id) {
    for (final p in all(c)) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Adresse de compilation correspondant à la catégorie, pour la rendre prioritaire sur le fournisseur recommandé.
  String _buildTimeUrl(ServiceCategory c) {
    switch (c) {
      case ServiceCategory.tiles:
        return config.tilesUrl;
      case ServiceCategory.glyphs:
        return config.glyphsUrl;
      case ServiceCategory.routing:
        return config.valhallaUrl;
      case ServiceCategory.geocoding:
      case ServiceCategory.reverse:
        return config.geocoderUrl;
      case ServiceCategory.transit:
        return config.otpUrl;
      case ServiceCategory.roadData:
        return config.overpassUrl;
      case ServiceCategory.account:
      case ServiceCategory.reports:
        return config.apiUrl;
      default:
        return '';
    }
  }

  String _buildTimeAdapter(ServiceCategory c) {
    switch (c) {
      case ServiceCategory.geocoding:
      case ServiceCategory.reverse:
        return 'nominatim';
      case ServiceCategory.transit:
        return 'otp';
      case ServiceCategory.account:
      case ServiceCategory.reports:
        return 'strasse-api';
      default:
        return ProviderCatalog.recommendedFor(c).adapter;
    }
  }

  /// Fournisseur actif d'une catégorie.
  ServiceProvider selected(ServiceCategory c) {
    final id = settings.providerSelections[c.id];
    if (id != null) {
      final p = _byId(c, id);
      if (p != null) return p;
    }
    final fromBuild = _buildTimeUrl(c).trim();
    if (fromBuild.isNotEmpty) {
      return ServiceProvider(
        id: 'build-${c.id}',
        category: c,
        name: 'Configuration de l\'application',
        description: 'Adresse fournie à la compilation (config/env.json).',
        baseUrl: fromBuild,
        adapter: _buildTimeAdapter(c),
        fallbackGroup: ProviderCatalog.recommendedFor(c).fallbackGroup,
        custom: true,
      );
    }
    return ProviderCatalog.recommendedFor(c);
  }

  /// Vrai si l'utilisateur est revenu (ou n'a jamais quitté) le fournisseur recommandé.
  bool isRecommendedSelected(ServiceCategory c) => selected(c).id == ProviderCatalog.recommendedFor(c).id && !settings.providerSelections.containsKey(c.id) ||
      settings.providerSelections[c.id] == ProviderCatalog.recommendedFor(c).id;

  /// Valeur d'un identifiant : saisie utilisateur, sinon valeur de compilation.
  String credential(ServiceProvider p, String key) {
    final user = credentials['${p.id}.$key']?.trim() ?? '';
    if (user.isNotEmpty) return user;
    switch ('${p.adapter}.$key') {
      case 'supabase.url':
        return config.supabaseUrl.trim();
      case 'supabase.anonKey':
        return config.supabaseAnonKey.trim();
      case 'opentripmap.apiKey':
        return config.openTripMapKey.trim();
      case 'spotify.clientId':
        return config.spotifyClientId.trim();
      case 'google-places.apiKey':
        return config.googlePlacesApiKey.trim();
    }
    return '';
  }

  /// Adresse de base utilisable du fournisseur actif, ou chaîne vide si elle doit encore être renseignée.
  String url(ServiceCategory c) => normalize(urlOf(selected(c)));

  String urlOf(ServiceProvider p) {
    if (p.kind == ProviderKind.credentials) {
      final u = credential(p, 'url');
      if (u.isNotEmpty) return u;
    }
    return p.baseUrl;
  }

  /// Fournisseurs à essayer dans l'ordre : le fournisseur actif, puis (si le basculement est actif) les fournisseurs
  /// équivalents intégrés du même groupe, sans doublon d'adresse. Les adresses vides sont ignorées.
  List<ServiceProvider> candidates(ServiceCategory c) {
    final first = selected(c);
    final out = <ServiceProvider>[first];
    if (settings.autoFallback && first.fallbackGroup.isNotEmpty) {
      for (final p in ProviderCatalog.of(c)) {
        if (p.id != first.id && p.fallbackGroup == first.fallbackGroup && p.adapter == first.adapter) out.add(p);
      }
    }
    final seen = <String>{};
    return [
      for (final p in out)
        if (p.kind == ProviderKind.native || p.kind == ProviderKind.link || (urlOf(p).isNotEmpty && seen.add(normalize(urlOf(p))))) p,
    ];
  }

  /// Fournisseurs cartographiques à essayer, dans l'ordre : sélection, fournisseur direct
  /// OpenFreeMap, puis style indépendant VersaTiles. Les styles OpenFreeMap Liberty,
  /// Bright et Positron ne constituent pas des secours indépendants entre eux.
  List<ServiceProvider> mapCandidates() {
    final selectedProvider = selected(ServiceCategory.tiles);
    final ordered = <ServiceProvider>[selectedProvider];
    if (settings.autoFallback) {
      for (final id in const ['openfreemap', 'versatiles-demo']) {
        final fallback = _byId(ServiceCategory.tiles, id);
        if (fallback != null && fallback.id != selectedProvider.id) ordered.add(fallback);
      }
    }
    final seen = <String>{};
    return [
      for (final provider in ordered)
        if (urlOf(provider).trim().isNotEmpty &&
            (provider.adapter == 'styleurl' || provider.adapter == 'tilejson') &&
            seen.add('${provider.adapter}|${normalize(urlOf(provider))}'))
          provider,
    ];
  }

  /// Source cartographique : style prêt à l'emploi (URL) ou tuiles vectorielles + polices Strasse.
  MapSourceConfig mapSource({ServiceProvider? provider}) {
    final tiles = provider ?? selected(ServiceCategory.tiles);
    final tilesUrl = normalize(urlOf(tiles));
    if (tiles.adapter == 'styleurl') return MapSourceConfig(tilesUrl: '', glyphsUrl: '', styleUrl: tilesUrl);
    if (tiles.adapter == 'tilejson') return MapSourceConfig(tilesUrl: tilesUrl, glyphsUrl: url(ServiceCategory.glyphs));
    return const MapSourceConfig(tilesUrl: '', glyphsUrl: '');
  }

  static String normalize(String u) {
    final v = u.trim();
    return v.endsWith('/') && !v.contains('{') ? v.substring(0, v.length - 1) : v;
  }
}

/// Ce dont la carte a besoin : soit un style complet [styleUrl], soit [tilesUrl] et [glyphsUrl].
class MapSourceConfig {
  const MapSourceConfig({required this.tilesUrl, required this.glyphsUrl, this.styleUrl});
  final String tilesUrl;
  final String glyphsUrl;
  final String? styleUrl;

  bool get available => (styleUrl ?? '').isNotEmpty || tilesUrl.isNotEmpty;
}
