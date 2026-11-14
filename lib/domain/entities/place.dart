import 'package:strasse/core/core.dart';

/// Lieu géographique (résultat de recherche, favori, destination récente…).
/// Les champs facultatifs ne sont renseignés que si la source les fournit : rien n'est inventé.
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.point,
    this.address,
    this.category,
    this.phone,
    this.website,
    this.openingHours,
    this.description,
    this.source = 'geocoder',
  });

  final String id;
  final String name;
  final GeoPoint point;
  final String? address;
  final String? category;
  final String? phone;
  final String? website;

  /// Horaires au format OpenStreetMap (`opening_hours`), affichés tels quels.
  final String? openingHours;
  final String? description;

  /// geocoder | coordinates | favorite | history | map
  final String source;

  String get coordsLabel => '${point.lat.toStringAsFixed(5)}, ${point.lon.toStringAsFixed(5)}';
  String get title => name.isNotEmpty ? name : (address ?? coordsLabel);

  /// Adresse sans répéter le nom en tête.
  String? get subtitle {
    final a = address;
    if (a == null || a.isEmpty) return category;
    if (name.isNotEmpty && a.startsWith(name)) {
      final rest = a.substring(name.length).replaceFirst(RegExp(r'^[,\s]+'), '');
      return rest.isEmpty ? category : rest;
    }
    return a;
  }

  Place copyWith({String? name, String? source, String? id}) => Place(
        id: id ?? this.id,
        name: name ?? this.name,
        point: point,
        address: address,
        category: category,
        phone: phone,
        website: website,
        openingHours: openingHours,
        description: description,
        source: source ?? this.source,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': point.lat,
        'lon': point.lon,
        'address': address,
        'category': category,
        'phone': phone,
        'website': website,
        'openingHours': openingHours,
        'description': description,
        'source': source,
      };

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        point: GeoPoint((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        address: j['address'] as String?,
        category: j['category'] as String?,
        phone: j['phone'] as String?,
        website: j['website'] as String?,
        openingHours: j['openingHours'] as String?,
        description: j['description'] as String?,
        source: (j['source'] as String?) ?? 'geocoder',
      );

  factory Place.fromCoordinates(GeoPoint p, {String? address}) => Place(
        id: 'coords:${p.lat.toStringAsFixed(6)},${p.lon.toStringAsFixed(6)}',
        name: '',
        point: p,
        address: address,
        category: 'Coordonnées GPS',
        source: 'coordinates',
      );

  /// Analyse un résultat Nominatim (`format=jsonv2`, `addressdetails=1`, `extratags=1`).
  factory Place.fromNominatim(Map<String, dynamic> j) {
    final display = (j['display_name'] as String?) ?? '';
    final nameField = (j['name'] as String?) ?? '';
    final extra = (j['extratags'] is Map) ? Map<String, dynamic>.from(j['extratags'] as Map) : <String, dynamic>{};
    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = extra[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    final osmType = j['osm_type'];
    final osmId = j['osm_id'];
    final id = (osmType != null && osmId != null) ? 'osm:$osmType$osmId' : 'nominatim:${j['place_id']}';
    final name = nameField.isNotEmpty ? nameField : (display.contains(',') ? display.split(',').first.trim() : display);
    return Place(
      id: id,
      name: name,
      point: GeoPoint(double.parse('${j['lat']}'), double.parse('${j['lon']}')),
      address: display.isEmpty ? null : display,
      category: categoryLabel('${j['category'] ?? ''}', '${j['type'] ?? ''}'),
      phone: pick(['phone', 'contact:phone']),
      website: pick(['website', 'contact:website']),
      openingHours: pick(['opening_hours']),
      description: pick(['description']),
    );
  }

  static const Map<String, String> _typeLabels = {
    'fuel': 'Station-service',
    'parking': 'Parking',
    'restaurant': 'Restaurant',
    'fast_food': 'Restauration rapide',
    'cafe': 'Café',
    'bar': 'Bar',
    'pharmacy': 'Pharmacie',
    'hospital': 'Hôpital',
    'clinic': 'Clinique',
    'bank': 'Banque',
    'atm': 'Distributeur',
    'charging_station': 'Borne de recharge',
    'toilets': 'Toilettes',
    'hotel': 'Hôtel',
    'guest_house': 'Chambre d\'hôtes',
    'hostel': 'Auberge',
    'museum': 'Musée',
    'attraction': 'Site touristique',
    'viewpoint': 'Point de vue',
    'supermarket': 'Supermarché',
    'bakery': 'Boulangerie',
    'school': 'École',
    'university': 'Université',
    'station': 'Gare',
    'bus_stop': 'Arrêt de bus',
    'city': 'Ville',
    'town': 'Ville',
    'village': 'Village',
    'hamlet': 'Hameau',
    'suburb': 'Quartier',
    'house': 'Adresse',
    'residential': 'Rue',
    'monument': 'Monument',
    'castle': 'Château',
    'place_of_worship': 'Lieu de culte',
    'police': 'Police',
    'post_office': 'Bureau de poste',
    'administrative': 'Zone administrative',
  };

  static String? categoryLabel(String category, String type) {
    final t = _typeLabels[type];
    if (t != null) return t;
    if (type.isEmpty) return null;
    final s = type.replaceAll('_', ' ');
    return s[0].toUpperCase() + s.substring(1);
  }
}
