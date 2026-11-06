import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/strasse_api.dart';
import 'package:strasse/domain/domain.dart';

class TrafficState {
  const TrafficState({
    this.snapshot = TrafficSnapshot.empty,
    this.loading = false,
    this.message,
    this.configured = false,
  });

  final TrafficSnapshot snapshot;
  final bool loading;

  /// Message d'état affiché à l'utilisateur (zone trop grande, serveur indisponible…).
  final String? message;
  final bool configured;

  /// Événements affichables sur la carte : signalements actifs et incidents du fournisseur externe.
  List<MapEvent> get events {
    final now = DateTime.now();
    return [
      for (final r in snapshot.reports)
        if (r.isActive(now)) MapEvent(id: 'report:${r.id}', type: r.type, point: r.point, report: r),
      for (final i in snapshot.incidents) MapEvent(id: 'incident:${i.id}', type: i.category, point: i.point, incident: i),
    ];
  }

  TrafficState copyWith({TrafficSnapshot? snapshot, bool? loading, String? message, bool clearMessage = false, bool? configured}) => TrafficState(
        snapshot: snapshot ?? this.snapshot,
        loading: loading ?? this.loading,
        message: clearMessage ? null : (message ?? this.message),
        configured: configured ?? this.configured,
      );
}

/// Informations routières : signalements de la communauté (backend Strasse) et incidents d'un fournisseur externe.
/// Aucune donnée n'est inventée : sans serveur ou sans fournisseur, les listes restent vides et l'interface l'explique.
class TrafficController extends StateNotifier<TrafficState> {
  TrafficController(this._api) : super(TrafficState(configured: _api.configured));

  StrasseApi _api;
  GeoBounds? _lastBounds;
  DateTime _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);

  void updateApi(StrasseApi api) {
    _api = api;
    state = TrafficState(configured: api.configured);
    _lastBounds = null;
  }

  Future<void> refresh(GeoBounds bounds, {bool force = false}) async {
    if (!_api.configured) {
      state = const TrafficState(configured: false, message: null);
      return;
    }
    if (bounds.lonSpan > 2 || bounds.latSpan > 2) {
      state = state.copyWith(message: 'Zoomez pour afficher les signalements et incidents.', loading: false, configured: true);
      return;
    }
    final now = DateTime.now();
    if (!force && now.difference(_lastFetch).inSeconds < 4 && _lastBounds != null) {
      final c = _lastBounds!;
      if (c.contains(bounds.center) && (c.lonSpan - bounds.lonSpan).abs() < c.lonSpan * 0.5) return;
    }
    _lastFetch = now;
    _lastBounds = bounds;
    state = state.copyWith(loading: true, clearMessage: true, configured: true);

    List<CommunityReport> reports = state.snapshot.reports;
    List<ExternalIncident> incidents = const [];
    var externalAvailable = false;
    String? provider;
    String? message;
    try {
      reports = await _api.reports(bounds);
    } catch (e) {
      message = toFailure(e).message;
    }
    try {
      final r = await _api.incidents(bounds);
      incidents = r.incidents;
      externalAvailable = r.available;
      provider = r.provider;
    } catch (e) {
      message ??= toFailure(e).message;
    }
    state = state.copyWith(
      snapshot: TrafficSnapshot(reports: reports, incidents: incidents, externalAvailable: externalAvailable, provider: provider, fetchedAt: DateTime.now()),
      loading: false,
      message: message,
      clearMessage: message == null,
    );
  }

  /// Met à jour un signalement après confirmation ou invalidation.
  void replaceReport(CommunityReport updated) {
    final list = [for (final r in state.snapshot.reports) r.id == updated.id ? updated : r];
    state = state.copyWith(
      snapshot: TrafficSnapshot(
        reports: list,
        incidents: state.snapshot.incidents,
        externalAvailable: state.snapshot.externalAvailable,
        provider: state.snapshot.provider,
        fetchedAt: state.snapshot.fetchedAt,
      ),
    );
  }

  void addReport(CommunityReport r) {
    if (state.snapshot.reports.any((x) => x.id == r.id)) {
      replaceReport(r);
      return;
    }
    state = state.copyWith(
      snapshot: TrafficSnapshot(
        reports: [...state.snapshot.reports, r],
        incidents: state.snapshot.incidents,
        externalAvailable: state.snapshot.externalAvailable,
        provider: state.snapshot.provider,
        fetchedAt: state.snapshot.fetchedAt,
      ),
    );
  }
}
