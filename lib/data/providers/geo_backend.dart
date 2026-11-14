import 'dart:async';

import 'package:dio/dio.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/domain/domain.dart';

/// Source de géocodage (Nominatim, Photon…). Les adaptateurs convertissent chaque format d'API en [Place].
abstract class GeoBackend {
  bool get allowsAutocomplete;

  Future<List<Place>> search(
    String query, {
    GeoPoint? near,
    GeoBounds? bounds,
    bool bounded = false,
    int limit = 8,
    CancelToken? cancel,
  });

  Future<Place?> reverse(GeoPoint p, {CancelToken? cancel});
}

/// File d'attente : exécute les tâches l'une après l'autre en respectant un intervalle minimal entre deux démarrages.
/// Utilisée pour le serveur public Nominatim (1 requête par seconde pour toute l'application).
class RateGate {
  RateGate(this.minInterval);

  final Duration minInterval;
  Future<void> _tail = Future<void>.value();
  DateTime _next = DateTime.fromMillisecondsSinceEpoch(0);

  Future<T> run<T>(Future<T> Function() job) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      final wait = _next.difference(DateTime.now());
      if (!wait.isNegative) await Future<void>.delayed(wait);
      try {
        completer.complete(await job());
      } catch (e, st) {
        completer.completeError(e, st);
      }
      _next = DateTime.now().add(minInterval);
    });
    return completer.future;
  }
}

/// Cache mémoire avec durée de vie, borné.
class TtlCache<V> {
  TtlCache({this.ttl = const Duration(minutes: 10), this.maxEntries = 120});

  final Duration ttl;
  final int maxEntries;
  final Map<String, ({DateTime at, V value})> _m = {};

  V? get(String key) {
    final e = _m[key];
    if (e == null) return null;
    if (DateTime.now().difference(e.at) > ttl) {
      _m.remove(key);
      return null;
    }
    return e.value;
  }

  void put(String key, V value) {
    _m.remove(key);
    _m[key] = (at: DateTime.now(), value: value);
    while (_m.length > maxEntries) {
      _m.remove(_m.keys.first);
    }
  }
}

/// Essaie chaque fournisseur dans l'ordre. Passe au suivant sur panne réseau, délai dépassé, 5xx ou 429 ;
/// une erreur « client » (requête invalide) est renvoyée telle quelle. Un fournisseur en échec est mis de côté 2 minutes.
class FailoverRunner {
  FailoverRunner._();

  static final Map<String, DateTime> _benched = {};

  static bool _retriable(Failure f) =>
      f.kind == FailureKind.offline || f.kind == FailureKind.timeout || f.kind == FailureKind.server || f.code == 'rate_limited';

  /// [retryClientErrors] : pour la recherche d'adresses, un 403/404/400 d'un serveur public ne doit pas
  /// empêcher d'essayer le suivant (quota dépassé, instance mal configurée, route absente).
  static Future<T> run<T>(List<String> keys, Future<T> Function(int index) attempt, {bool retryClientErrors = false}) async {
    if (keys.isEmpty) throw const Failure(FailureKind.notConfigured, 'Aucun fournisseur disponible pour ce service.');
    final now = DateTime.now();
    final order = <int>[
      for (var i = 0; i < keys.length; i++)
        if ((_benched[keys[i]] ?? now).isBefore(now) || !_benched.containsKey(keys[i])) i,
      for (var i = 0; i < keys.length; i++)
        if (_benched.containsKey(keys[i]) && _benched[keys[i]]!.isAfter(now)) i,
    ];
    Failure? last;
    for (final i in order) {
      try {
        final r = await attempt(i);
        _benched.remove(keys[i]);
        return r;
      } catch (e) {
        final f = toFailure(e);
        last = f;
        if (!_retriable(f) && !(retryClientErrors && f.kind == FailureKind.client && f.code != 'cancelled')) rethrow;
        _benched[keys[i]] = DateTime.now().add(const Duration(minutes: 2));
      }
    }
    throw last ?? Failure.unknown();
  }
}
