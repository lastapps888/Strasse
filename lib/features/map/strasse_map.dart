import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:strasse/app/widgets/vehicle_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/map/map_style_builder.dart';
import 'package:strasse/features/map/poi_badges.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:strasse/features/settings/settings_model.dart';

/// Épingle affichée sur la carte (destination, étape, résultat de recherche…).
class MapPin {
  const MapPin({required this.id, required this.point, required this.color, this.radius = 9, this.onTap});
  final String id;
  final GeoPoint point;
  final Color color;
  final double radius;
  final VoidCallback? onTap;
}

/// Ligne supplémentaire (tronçon de transport en commun, trace…).
class MapPolyline {
  const MapPolyline({required this.points, required this.color, this.width = 5, this.dashed = false, this.tag});

  /// Objet renvoyé à [StrasseMapController.onLineTag] quand la ligne est touchée.
  final Object? tag;
  final List<GeoPoint> points;
  final Color color;
  final double width;
  final bool dashed;
}

ml.LatLng _ll(GeoPoint p) => ml.LatLng(p.lat, p.lon);

/// Pilote la carte : tout ce qui est dessiné dessus (itinéraires, position, épingles, événements) est mémorisé ici
/// et redessiné automatiquement après un changement de style (clair/sombre, personnalisation…).
class _FollowCam {
  const _FollowCam({required this.zoom, required this.tilt, required this.useHeading, this.fallbackBearing});
  final double zoom;
  final double tilt;
  final bool useHeading;
  final double? fallbackBearing;
}

class StrasseMapController {
  ml.MapLibreMapController? _c;
  Future<void> _queue = Future.value();

  List<RouteOption> _routes = const [];
  int _selected = 0;
  Color _routeColor = const Color(0xFF1F7FD1);
  List<MapPin> _pins = const [];
  List<MapEvent> _events = const [];
  List<MapPolyline> _extraLines = const [];
  List<MapPin> _transitStops = const [];
  List<MapPin> _poiPins = const [];
  GeoPoint? _user;
  bool _userStale = false;
  double _userAccuracy = 0;
  Color _userColor = const Color(0xFF1F7FD1);

  ml.Circle? _userHalo;
  ml.Circle? _userDot;
  /// Véhicule : source GeoJSON + couche `symbol` (permet `icon-allow-overlap` et une rotation alignée sur la carte,
  /// que `SymbolOptions` n'expose pas).
  bool _vehicleLayerReady = false;
  bool _vehicleShown = false;
  VehicleIcon _vehicle = VehicleIcon.arrow;
  bool _useVehicle = false;
  double _userBearing = 0;
  String? _vehicleImageKey;
  final List<ml.Line> _lines = [];
  final List<ml.Circle> _circles = [];
  final Map<String, int> _lineToRoute = {};
  final Map<String, Object> _lineToTag = {};
  final Map<String, MapEvent> _circleToEvent = {};
  final Map<String, MapPin> _circleToPin = {};
  bool _externalSatelliteEnabled = false;

  static const String _satelliteWorldSource = 'strasse-ext-satellite-world-source';
  static const String _satelliteFranceSource = 'strasse-ext-satellite-france-source';
  static const String _satelliteWorldLayer = 'strasse-ext-satellite-world-layer';
  static const String _satelliteFranceLayer = 'strasse-ext-satellite-france-layer';

  void Function(int routeIndex)? onRouteTapped;
  void Function(MapEvent event)? onEventTapped;
  void Function(Object tag)? onLineTag;
  VoidCallback? onUserMoved;
  DateTime _lastProgrammatic = DateTime.fromMillisecondsSinceEpoch(0);
  bool trackUserGestures = false;

  bool get isReady => _c != null;

  void attach(ml.MapLibreMapController controller) {
    _c = controller;
    controller.onCircleTapped.add(_circleTapped);
    controller.onLineTapped.add(_lineTapped);
    controller.addListener(_cameraChanged);
  }

  void detach() {
    _stopGlide();
    _c?.removeListener(_cameraChanged);
    _c = null;
  }

  void _cameraChanged() {
    if (!trackUserGestures) return;
    if (DateTime.now().difference(_lastProgrammatic).inMilliseconds > 1500) onUserMoved?.call();
  }

  void _circleTapped(ml.Circle c) {
    final e = _circleToEvent[c.id];
    if (e != null) {
      onEventTapped?.call(e);
      return;
    }
    _circleToPin[c.id]?.onTap?.call();
  }

  void _lineTapped(ml.Line l) {
    final i = _lineToRoute[l.id];
    if (i != null) {
      onRouteTapped?.call(i);
      return;
    }
    final tag = _lineToTag[l.id];
    if (tag != null) onLineTag?.call(tag);
  }

  Future<void> _enqueue(Future<void> Function() task) {
    _queue = _queue.then((_) async {
      try {
        await task();
      } catch (_) {
        // Un échec de dessin (carte détruite, style en rechargement) ne doit jamais planter l'application.
      }
    });
    return _queue;
  }

  /// Active l'imagerie satellite au-dessus de n'importe quel style fournisseur distant.
  /// Le style du fournisseur n'est jamais remplacé : seules deux sources raster sont ajoutées.
  Future<void> setExternalSatelliteEnabled(bool enabled) {
    _externalSatelliteEnabled = enabled;
    return _enqueue(_applyExternalSatellite);
  }

  Future<void> _applyExternalSatellite() async {
    final c = _c;
    if (c == null) return;

    final layerIds = (await c.getLayerIds()).whereType<String>().toSet();
    if (!_externalSatelliteEnabled) {
      for (final id in const [_satelliteFranceLayer, _satelliteWorldLayer]) {
        if (layerIds.contains(id)) {
          await c.removeLayer(id);
        }
      }
      final sourceIds = (await c.getSourceIds()).toSet();
      for (final id in const [_satelliteFranceSource, _satelliteWorldSource]) {
        if (sourceIds.contains(id)) {
          await c.removeSource(id);
        }
      }
      return;
    }

    final sourceIds = (await c.getSourceIds()).toSet();
    if (!sourceIds.contains(_satelliteWorldSource)) {
      await c.addSource(
        _satelliteWorldSource,
        const ml.RasterSourceProperties(
          tiles: ['https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless_3857/default/g/{z}/{y}/{x}.jpg'],
          tileSize: 256,
          maxzoom: 13,
          attribution: 'EOxCloudless https://cloudless.eox.at by EOX IT Services GmbH (Contains modified Copernicus Sentinel data 2016 & 2017)',
        ),
      );
    }
    if (!sourceIds.contains(_satelliteFranceSource)) {
      await c.addSource(
        _satelliteFranceSource,
        const ml.RasterSourceProperties(
          tiles: [
            'https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=ORTHOIMAGERY.ORTHOPHOTOS&STYLE=normal&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/jpeg',
          ],
          tileSize: 256,
          minzoom: 6,
          maxzoom: 19,
          bounds: [-5.6, 41.2, 10.0, 51.2],
          attribution: 'Orthophotographies © IGN (Licence Ouverte)',
        ),
      );
    }

    // Place les images au-dessus des aplats de fond et sous les premières routes/étiquettes
    // du style chargé. Les ID des couches sont lus dans le style original du fournisseur.
    String? belowLayerId;
    final rawStyle = await c.getStyle();
    if (rawStyle != null && rawStyle.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawStyle);
        final layers = decoded is Map ? decoded['layers'] : null;
        if (layers is List) {
          for (final layer in layers) {
            if (layer is Map &&
                layer['id'] is String &&
                const {'line', 'symbol', 'fill-extrusion'}.contains(layer['type'])) {
              belowLayerId = layer['id'] as String;
              break;
            }
          }
        }
      } on FormatException {
        // Certains styles propriétaires ne sont pas exposés sous forme de JSON exploitable.
      }
    }

    final existingLayers = (await c.getLayerIds()).whereType<String>().toSet();
    if (!existingLayers.contains(_satelliteWorldLayer)) {
      await c.addRasterLayer(
        _satelliteWorldSource,
        _satelliteWorldLayer,
        const ml.RasterLayerProperties(rasterFadeDuration: 150),
        belowLayerId: belowLayerId,
        maxzoom: 13,
      );
    }
    if (!existingLayers.contains(_satelliteFranceLayer)) {
      await c.addRasterLayer(
        _satelliteFranceSource,
        _satelliteFranceLayer,
        const ml.RasterLayerProperties(rasterFadeDuration: 150),
        belowLayerId: belowLayerId,
        minzoom: 6,
        maxzoom: 19,
      );
    }
  }

  // ------------------------------------------------------------ État souhaité

  Future<void> setRoutes(List<RouteOption> routes, int selected, Color color) {
    _routes = routes;
    _selected = selected;
    _routeColor = color;
    return _enqueue(_drawRoutes);
  }

  Future<void> setPins(List<MapPin> pins) {
    _pins = pins;
    return _enqueue(_drawPins);
  }

  Future<void> setEvents(List<MapEvent> events) {
    _events = events;
    return _enqueue(_drawPins);
  }

  /// Arrêts de transport en commun (cercles plus petits que les résultats de recherche, dessinés dessous).
  Future<void> setTransitStops(List<MapPin> stops) {
    _transitStops = stops;
    return _enqueue(_drawPins);
  }

  /// Hôtels, restaurants et sites touristiques de la zone visible.
  Future<void> setPoiPins(List<MapPin> pins) {
    _poiPins = pins;
    return _enqueue(_drawPins);
  }

  Future<void> setExtraLines(List<MapPolyline> lines) {
    _extraLines = lines;
    return _enqueue(_drawRoutes);
  }

  /// Remplace le point bleu par le pictogramme du véhicule choisi (null ou flèche : point classique).
  Future<void> setVehicle(VehicleIcon? icon) {
    final use = icon != null;
    if (use == _useVehicle && (icon ?? _vehicle) == _vehicle) return Future.value();
    _useVehicle = use;
    if (icon != null) _vehicle = icon;
    return _enqueue(() => _drawUserNow(force: true));
  }

  Future<void> setUser(GeoPoint? p, {double accuracy = 0, bool stale = false, Color? color, double? bearing}) {
    _userAccuracy = accuracy;
    _userStale = stale;
    if (color != null) _userColor = color;
    if (p == null) {
      _stopGlide();
      _user = null;
      _shown = null;
      return _enqueue(_drawUser);
    }
    final now = DateTime.now();
    final newBearing = bearing ?? _userBearing;
    final first = _shown == null || _user == null;
    // Saut important (changement de lieu, reprise après une longue pause) : on s'y place sans glisser.
    if (first || distanceM(_shown!, p) > 250) {
      _stopGlide();
      _user = p;
      _shown = p;
      _userBearing = newBearing;
      _shownBearing = newBearing;
      _lastFixAt = now;
      return _enqueue(_drawUser);
    }
    // Glissement de la position affichée vers la nouvelle mesure GPS, sur la durée réellement écoulée entre deux
    // mesures (jamais de téléportation) ; la précision et le cap affichés restent ceux du GPS.
    final gap = _lastFixAt == null ? 1000 : now.difference(_lastFixAt!).inMilliseconds;
    _lastFixAt = now;
    _glideFrom = _shown;
    _glideFromBearing = _shownBearing;
    _user = p;
    _userBearing = newBearing;
    _glideStart = now;
    _glideMs = gap.clamp(350, 1600);
    _startGlide();
    return _queue;
  }

  // ---------------------------------------------------------- Glissement

  GeoPoint? _shown; // position réellement dessinée
  double _shownBearing = 0;
  GeoPoint? _glideFrom;
  double _glideFromBearing = 0;
  DateTime _glideStart = DateTime.fromMillisecondsSinceEpoch(0);
  int _glideMs = 1000;
  DateTime? _lastFixAt;
  Timer? _glideTimer;
  bool _framePending = false;
  _FollowCam? _cam;

  /// Fait suivre la caméra au véhicule à chaque image (au lieu d'une animation par mesure GPS) : carte et véhicule
  /// restent synchronisés. `null` arrête le suivi.
  void setFollowCamera({double zoom = 16.5, double tilt = 0, bool useHeading = true, double? fallbackBearing}) {
    _cam = _FollowCam(zoom: zoom, tilt: tilt, useHeading: useHeading, fallbackBearing: fallbackBearing);
    if (_glideTimer == null && _shown != null) _enqueue(_frame);
  }

  void clearFollowCamera() => _cam = null;

  void _startGlide() {
    _glideTimer ??= Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (_framePending) return;
      _framePending = true;
      _enqueue(_frame);
    });
  }

  void _stopGlide() {
    _glideTimer?.cancel();
    _glideTimer = null;
    _framePending = false;
  }

  static double _lerpAngle(double a, double b, double t) {
    var d = (b - a) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return (a + d * t) % 360;
  }

  Future<void> _frame() async {
    _framePending = false;
    final c = _c;
    final from = _glideFrom;
    final to = _user;
    if (c == null || to == null) {
      _stopGlide();
      return;
    }
    final elapsed = DateTime.now().difference(_glideStart).inMilliseconds;
    final t = from == null ? 1.0 : (elapsed / _glideMs).clamp(0.0, 1.0);
    if (from != null) {
      _shown = GeoPoint(from.lat + (to.lat - from.lat) * t, from.lon + (to.lon - from.lon) * t);
      _shownBearing = _lerpAngle(_glideFromBearing, _userBearing, math.min(1.0, t * 1.5));
    } else {
      _shown = to;
      _shownBearing = _userBearing;
    }
    await _drawUserNow();
    final cam = _cam;
    final shown = _shown;
    if (cam != null && shown != null) {
      _lastProgrammatic = DateTime.now();
      try {
        await c.moveCamera(ml.CameraUpdate.newCameraPosition(ml.CameraPosition(
          target: _ll(shown),
          zoom: cam.zoom,
          bearing: cam.useHeading ? _shownBearing : (cam.fallbackBearing ?? 0),
          tilt: cam.tilt,
        )));
      } catch (_) {}
    }
    // Fin du glissement : on arrête la minuterie (elle repart à la mesure suivante).
    if (t >= 1.0) _stopGlide();
  }

  /// Redessine tout après un (re)chargement de style.
  Future<void> reapply() => _enqueue(() async {
        final c = _c;
        if (c == null) return;
        await _applyExternalSatellite();
        await c.clearLines();
        await c.clearCircles();
        _lines.clear();
        _circles.clear();
        _lineToRoute.clear();
        _lineToTag.clear();
        _circleToEvent.clear();
        _circleToPin.clear();
        _userDot = null;
        _userHalo = null;
        _vehicleLayerReady = false;
        _vehicleShown = false;
        _vehicleImageKey = null;
        await _registerPoiBadges(c);
        await _drawRoutesNow();
        await _drawPinsNow();
        await _drawUserNow();
      });

  Future<void> _registerPoiBadges(ml.MapLibreMapController c) async {
    try {
      for (final b in [...PoiBadges.all, PoiBadges.other]) {
        await c.addImage(b.image, await PoiBadges.render(b));
      }
    } catch (_) {
      // Image déjà présente dans le style rechargé : sans conséquence.
    }
  }

  /// Lieu déjà repéré par un badge ou un nom sur la carte, sous le point touché (null si rien n'y est affiché).
  Future<Place?> placeAt(math.Point<double> screen) async {
    final c = _c;
    if (c == null) return null;
    try {
      final rect = Rect.fromCenter(center: Offset(screen.x, screen.y), width: 36, height: 36);
      final found = await c.queryRenderedFeaturesInRect(rect, const ['poi-dots', 'poi-labels'], null);
      for (final f in found) {
        if (f is! Map) continue;
        final props = f['properties'];
        final geom = f['geometry'];
        if (props is! Map || geom is! Map) continue;
        final coords = geom['coordinates'];
        if (coords is! List || coords.length < 2) continue;
        final name = '${props['name:fr'] ?? props['name'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        final cls = props['class'] is String ? props['class'] as String : null;
        final sub = props['subclass'] is String ? props['subclass'] as String : null;
        final lon = (coords[0] as num).toDouble();
        final lat = (coords[1] as num).toDouble();
        return Place(id: 'map:${lat.toStringAsFixed(6)},${lon.toStringAsFixed(6)}', name: name, point: GeoPoint(lat, lon), category: sub ?? cls, source: 'map');
      }
    } catch (_) {}
    return null;
  }

  // ----------------------------------------------------------------- Dessin

  Future<void> _drawRoutes() async {
    if (_c == null) return;
    await _drawRoutesNow();
    // La position doit rester au-dessus des lignes.
    await _drawUserNow(force: true);
  }

  Future<void> _drawRoutesNow() async {
    final c = _c;
    if (c == null) return;
    if (_lines.isNotEmpty) await c.removeLines(List.of(_lines));
    _lines.clear();
    _lineToRoute.clear();
    _lineToTag.clear();

    // Alternatives d'abord (dessous), puis l'itinéraire sélectionné avec son contour.
    for (var i = 0; i < _routes.length; i++) {
      if (i == _selected) continue;
      final line = await c.addLine(ml.LineOptions(
        geometry: _routes[i].shape.map(_ll).toList(),
        lineColor: hex(const Color(0xFF7C8796)),
        lineWidth: 6,
        lineOpacity: 0.85,
        lineJoin: 'round',
      ));
      _lines.add(line);
      _lineToRoute[line.id] = i;
    }
    if (_routes.isNotEmpty && _selected < _routes.length) {
      final pts = _routes[_selected].shape.map(_ll).toList();
      _lines.add(await c.addLine(ml.LineOptions(geometry: pts, lineColor: '#FFFFFF', lineWidth: 11, lineOpacity: 0.95, lineJoin: 'round')));
      final main = await c.addLine(ml.LineOptions(geometry: pts, lineColor: hex(_routeColor), lineWidth: 7, lineOpacity: 1, lineJoin: 'round'));
      _lines.add(main);
      _lineToRoute[main.id] = _selected;
    }
    for (final l in _extraLines) {
      final line = await c.addLine(ml.LineOptions(
        geometry: l.points.map(_ll).toList(),
        lineColor: hex(l.color),
        lineWidth: l.width,
        lineOpacity: 0.95,
        lineJoin: 'round',
        linePattern: null,
      ));
      _lines.add(line);
      if (l.tag != null) _lineToTag[line.id] = l.tag!;
    }
  }

  Future<void> _drawPins() async {
    if (_c == null) return;
    await _drawPinsNow();
    await _drawUserNow(force: true);
  }

  Future<void> _drawPinsNow() async {
    final c = _c;
    if (c == null) return;
    if (_circles.isNotEmpty) await c.removeCircles(List.of(_circles));
    _circles.clear();
    _circleToEvent.clear();
    _circleToPin.clear();

    for (final e in _events) {
      final circle = await c.addCircle(ml.CircleOptions(
        geometry: _ll(e.point),
        circleRadius: 10,
        circleColor: hex(e.type.color),
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2.5,
        circleOpacity: 0.95,
      ));
      _circles.add(circle);
      _circleToEvent[circle.id] = e;
    }
    for (final p in [..._transitStops, ..._poiPins]) {
      final circle = await c.addCircle(ml.CircleOptions(
        geometry: _ll(p.point),
        circleRadius: p.radius,
        circleColor: hex(p.color),
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      ));
      _circles.add(circle);
      _circleToPin[circle.id] = p;
    }
    for (final p in _pins) {
      final circle = await c.addCircle(ml.CircleOptions(
        geometry: _ll(p.point),
        circleRadius: p.radius,
        circleColor: hex(p.color),
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
      ));
      _circles.add(circle);
      _circleToPin[circle.id] = p;
    }
  }

  Future<void> _drawUser() async {
    if (_c == null) return;
    await _drawUserNow();
  }

  Future<void> _removeUser(ml.MapLibreMapController c) async {
    if (_userHalo != null) await c.removeCircle(_userHalo!);
    if (_userDot != null) await c.removeCircle(_userDot!);
    await _hideVehicle(c);
    _userHalo = null;
    _userDot = null;
  }

  static const _vehicleSource = 'strasse-vehicle-src';
  static const _vehicleLayer = 'strasse-vehicle-layer';

  Map<String, dynamic> _vehicleGeoJson(GeoPoint p, String image) => {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {'type': 'Point', 'coordinates': [p.lon, p.lat]},
            'properties': {'img': image, 'bearing': _shownBearing},
          },
        ],
      };

  Future<void> _showVehicle(ml.MapLibreMapController c, GeoPoint p, String image) async {
    final data = _vehicleGeoJson(p, image);
    if (!_vehicleLayerReady) {
      try {
        await c.addSource(_vehicleSource, ml.GeojsonSourceProperties(data: data));
        await c.addSymbolLayer(
          _vehicleSource,
          _vehicleLayer,
          ml.SymbolLayerProperties(
            iconImage: ['get', 'img'],
            iconSize: 0.42,
            iconRotate: ['get', 'bearing'],
            iconAllowOverlap: true,
            iconIgnorePlacement: true,
            iconRotationAlignment: 'map',
            iconPitchAlignment: 'map',
          ),
        );
        _vehicleLayerReady = true;
      } catch (_) {
        // La source existe déjà (style rechargé) : on la met simplement à jour ci-dessous.
        _vehicleLayerReady = true;
      }
    } else {
      await c.setGeoJsonSource(_vehicleSource, data);
    }
    _vehicleShown = true;
  }

  Future<void> _hideVehicle(ml.MapLibreMapController c) async {
    if (!_vehicleLayerReady || !_vehicleShown) return;
    try {
      await c.setGeoJsonSource(_vehicleSource, {'type': 'FeatureCollection', 'features': <dynamic>[]});
    } catch (_) {}
    _vehicleShown = false;
  }

  Future<void> _drawUserNow({bool force = false}) async {
    final c = _c;
    if (c == null) return;
    final p = _shown ?? _user;
    if (force || p == null) await _removeUser(c);
    if (p == null) return;
    final color = _userStale ? const Color(0xFF8A93A0) : _userColor;
    final vehicle = _useVehicle && _vehicle != VehicleIcon.arrow;
    // Halo = précision approximative (borné pour rester lisible).
    final haloPx = (_userAccuracy.clamp(10, 120) / 3).toDouble() + 12;
    if (_userHalo == null) {
      _userHalo = await c.addCircle(ml.CircleOptions(geometry: _ll(p), circleRadius: haloPx, circleColor: hex(color), circleOpacity: 0.18));
    } else {
      await c.updateCircle(_userHalo!, ml.CircleOptions(geometry: _ll(p), circleRadius: haloPx, circleColor: hex(color)));
    }
    if (vehicle) {
      final key = '${_vehicle.name}-${color.value}';
      if (_vehicleImageKey != key) {
        await c.addImage('vehicle-$key', await renderVehiclePng(_vehicle, color));
        _vehicleImageKey = key;
      }
      await _showVehicle(c, p, 'vehicle-$key');
      if (_userDot != null) {
        await c.removeCircle(_userDot!);
        _userDot = null;
      }
    } else {
      await _hideVehicle(c);
      if (_userDot == null) {
        _userDot = await c.addCircle(ml.CircleOptions(geometry: _ll(p), circleRadius: 8, circleColor: hex(color), circleStrokeColor: '#FFFFFF', circleStrokeWidth: 3));
      } else {
        await c.updateCircle(_userDot!, ml.CircleOptions(geometry: _ll(p), circleColor: hex(color)));
      }
    }
  }

  // ----------------------------------------------------------------- Caméra

  Future<void> flyTo(GeoPoint p, {double? zoom, double bearing = 0, double tilt = 0, int ms = 700}) async {
    final c = _c;
    if (c == null) return;
    _lastProgrammatic = DateTime.now();
    try {
      await c.animateCamera(
        ml.CameraUpdate.newCameraPosition(ml.CameraPosition(
          target: _ll(p),
          zoom: zoom ?? (c.cameraPosition?.zoom ?? 14),
          bearing: bearing,
          tilt: tilt,
        )),
        duration: Duration(milliseconds: ms),
      );
    } catch (_) {}
  }

  Future<void> fitPoints(List<GeoPoint> pts, {double left = 48, double top = 48, double right = 48, double bottom = 48}) async {
    final c = _c;
    if (c == null || pts.isEmpty) return;
    _lastProgrammatic = DateTime.now();
    final b = GeoBounds.fromPoints(pts);
    try {
      if (b.latSpan < 1e-5 && b.lonSpan < 1e-5) {
        await flyTo(pts.first, zoom: 15);
        return;
      }
      await c.animateCamera(
        ml.CameraUpdate.newLatLngBounds(
          ml.LatLngBounds(southwest: ml.LatLng(b.south, b.west), northeast: ml.LatLng(b.north, b.east)),
          left: left,
          top: top,
          right: right,
          bottom: bottom,
        ),
        duration: const Duration(milliseconds: 700),
      );
    } catch (_) {}
  }

  Future<void> zoomBy(double delta) async {
    final c = _c;
    if (c == null) return;
    _lastProgrammatic = DateTime.now();
    try {
      await c.animateCamera(ml.CameraUpdate.zoomBy(delta));
    } catch (_) {}
  }

  Future<void> resetNorth() async {
    final c = _c;
    final cam = c?.cameraPosition;
    if (c == null || cam == null) return;
    _lastProgrammatic = DateTime.now();
    try {
      await c.animateCamera(ml.CameraUpdate.newCameraPosition(ml.CameraPosition(target: cam.target, zoom: cam.zoom, bearing: 0, tilt: 0)));
    } catch (_) {}
  }

  double get bearing => _c?.cameraPosition?.bearing ?? 0;
  double get zoom => _c?.cameraPosition?.zoom ?? 0;
  GeoPoint? get center {
    final t = _c?.cameraPosition?.target;
    return t == null ? null : GeoPoint(t.latitude, t.longitude);
  }

  Future<GeoBounds?> visibleBounds() async {
    final c = _c;
    if (c == null) return null;
    try {
      final b = await c.getVisibleRegion();
      return GeoBounds(south: b.southwest.latitude, west: b.southwest.longitude, north: b.northeast.latitude, east: b.northeast.longitude);
    } catch (_) {
      return null;
    }
  }
}

/// Carte Strasse : style généré selon les réglages, crédits OpenStreetMap, état « serveur de cartes absent ».
class StrasseMap extends ConsumerStatefulWidget {
  const StrasseMap({
    super.key,
    required this.onReady,
    this.initialTarget,
    this.initialZoom = 14,
    this.forceDark,
    this.onTap,
    this.onLongPress,
    this.onPlaceTap,
    this.onCameraIdle,
    this.interactive = true,
    this.lockNorth = false,
    this.attributionBottomPadding = 8,
  });

  final void Function(StrasseMapController controller) onReady;
  final GeoPoint? initialTarget;
  final double initialZoom;

  /// Force le mode sombre ou clair (navigation de nuit) ; null suit les réglages.
  final bool? forceDark;
  final void Function(GeoPoint point)? onTap;
  final void Function(GeoPoint point)? onLongPress;

  /// Appelé quand on touche un lieu déjà marqué sur la carte (badge ou nom) : un seul toucher suffit.
  final void Function(Place place)? onPlaceTap;
  final VoidCallback? onCameraIdle;
  final bool interactive;

  /// Bloque rotation et inclinaison : la carte reste orientée nord (sélection de zone).
  final bool lockNorth;
  final double attributionBottomPadding;

  @override
  ConsumerState<StrasseMap> createState() => _StrasseMapState();
}

class _StrasseMapState extends ConsumerState<StrasseMap> {
  final StrasseMapController _controller = StrasseMapController();
  String _style = '';
  String _styleKey = '';

  @override
  void dispose() {
    _controller.detach();
    super.dispose();
  }

  String _buildStyle(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final config = ref.watch(appConfigProvider);
    final platform = MediaQuery.platformBrightnessOf(context);
    final brightness = widget.forceDark == null ? platform : (widget.forceDark! ? Brightness.dark : Brightness.light);
    final src = ref.watch(providerResolverProvider).mapSource();
    final key = [
      settings.mapStyle.name,
      settings.customRoadColor,
      settings.customBuildingColor,
      settings.customWaterColor,
      settings.customGreenColor,
      settings.showBuildings,
      settings.showPoi,
      settings.showTransit,
      settings.showCycleways,
      settings.showSatellite,
      settings.mapDensity,
      brightness.name,
      src.tilesUrl,
      src.glyphsUrl,
      src.styleUrl,
      config.mapFont,
      config.tilesAttribution,
      widget.forceDark,
    ].join('|');
    if (key == _styleKey) return _style;
    if (src.styleUrl != null) {
      // Style complet d'un fournisseur (ex. OpenFreeMap Liberty) : utilisé tel quel.
      _style = src.styleUrl!;
      _styleKey = key;
      return _style;
    }
    var palette = MapPalette.forSettings(settings, brightness);
    if (widget.forceDark == true && settings.mapStyle == MapStyleChoice.contrast) palette = MapPalette.contrast;
    _style = MapStyleBuilder.build(
      palette: palette,
      settings: settings,
      tilesUrl: src.tilesUrl,
      glyphsUrl: src.glyphsUrl,
      font: config.mapFont,
      attribution: config.tilesAttribution,
    );
    _styleKey = key;
    return _style;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppSettings>(settingsProvider, (previous, next) {
      if (previous?.showSatellite == next.showSatellite) return;
      final source = ref.read(providerResolverProvider).mapSource();
      _controller.setExternalSatelliteEnabled(source.styleUrl != null && next.showSatellite);
    });
    final config = ref.watch(appConfigProvider);
    final settings = ref.watch(settingsProvider);
    final style = _buildStyle(context);
    final hasTiles = ref.watch(providerResolverProvider).mapSource().available;
    final fix = ref.read(locationFixOnceProvider);
    final target = widget.initialTarget ?? fix ?? const GeoPoint(46.6, 2.4);
    final zoom = widget.initialTarget != null || fix != null ? widget.initialZoom : 5.2;
    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        ml.MapLibreMap(
          styleString: style,
          initialCameraPosition: ml.CameraPosition(target: _ll(target), zoom: zoom),
          onMapCreated: (c) {
            _controller.attach(c);
            widget.onReady(_controller);
          },
          onStyleLoadedCallback: () {
            // La couche satellite est un overlay raster indépendant du style de base :
            // elle doit aussi être réappliquée aux styles vectoriels générés par Strasse.
            _controller.setExternalSatelliteEnabled(ref.read(settingsProvider).showSatellite);
            _controller.reapply();
          },
          onMapClick: (math.Point<double> pt, ml.LatLng ll) async {
            if (widget.onPlaceTap != null) {
              final place = await _controller.placeAt(pt);
              if (place != null) {
                widget.onPlaceTap!(place);
                return;
              }
            }
            widget.onTap?.call(GeoPoint(ll.latitude, ll.longitude));
          },
          onMapLongClick: (math.Point<double> _, ml.LatLng ll) => widget.onLongPress?.call(GeoPoint(ll.latitude, ll.longitude)),
          onCameraIdle: widget.onCameraIdle,
          trackCameraPosition: true,
          compassEnabled: false,
          myLocationEnabled: false,
          rotateGesturesEnabled: widget.interactive && !widget.lockNorth,
          scrollGesturesEnabled: widget.interactive,
          zoomGesturesEnabled: widget.interactive,
          tiltGesturesEnabled: widget.interactive && !widget.lockNorth,
          minMaxZoomPreference: const ml.MinMaxZoomPreference(2, 20),
        ),
        if (!hasTiles)
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.paddingOf(context).top + 72,
            child: Material(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.map_outlined, color: cs.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Aucun serveur de cartes n\'est configuré : la carte reste vide. Renseignez l\'adresse des tuiles dans Réglages > Services.',
                        style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // Crédits obligatoires : OpenStreetMap + fournisseur de tuiles.
        Positioned(
          left: 8,
          bottom: widget.attributionBottomPadding,
          child: GestureDetector(
            onTap: () => launchUrl(Uri.parse(AppConfig.osmCopyrightUrl), mode: LaunchMode.externalApplication),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: cs.surface.withOpacity(0.8), borderRadius: BorderRadius.circular(8)),
              child: Text(
                [
                  AppConfig.osmAttribution,
                  if (config.tilesAttribution.isNotEmpty) config.tilesAttribution,
                  if (settings.showSatellite) 'EOxCloudless https://cloudless.eox.at by EOX IT Services GmbH (Contains modified Copernicus Sentinel data 2016 & 2017)',
                  if (settings.showSatellite) 'Orthophotographies © IGN (Licence Ouverte)',
                ].join(' · '),
                style: TextStyle(fontSize: 10, color: cs.onSurface.withOpacity(0.8)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
