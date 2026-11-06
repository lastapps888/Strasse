import 'package:flutter/material.dart';
import 'package:strasse/core/core.dart';

enum ReportType {
  accident('Accident', Icons.car_crash_rounded, Color(0xFFD32F2F)),
  roadwork('Travaux', Icons.construction_rounded, Color(0xFFF57C00)),
  slowdown('Ralentissement', Icons.traffic_rounded, Color(0xFFFBC02D)),
  closure('Route fermée', Icons.block_rounded, Color(0xFF7B1FA2)),
  obstacle('Obstacle', Icons.warning_amber_rounded, Color(0xFF5D4037)),
  danger('Danger temporaire', Icons.report_problem_rounded, Color(0xFFC62828)),
  other('Autre événement', Icons.more_horiz_rounded, Color(0xFF455A64));

  const ReportType(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;

  static ReportType fromName(String? n) => ReportType.values.firstWhere((t) => t.name == n, orElse: () => ReportType.other);
}

/// Signalement communautaire anonyme renvoyé par le backend.
class CommunityReport {
  const CommunityReport({
    required this.id,
    required this.type,
    required this.point,
    required this.createdAt,
    required this.expiresAt,
    required this.status,
    required this.confirmations,
    required this.rejections,
    required this.reliability,
  });

  final String id;
  final ReportType type;
  final GeoPoint point;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String status;
  final int confirmations;
  final int rejections;

  /// Estimation entre 0 et 1, jamais une certitude.
  final double reliability;

  bool isActive(DateTime now) => status == 'active' && expiresAt.isAfter(now);

  /// Libellé prudent : une information communautaire n'est jamais présentée comme certaine.
  String get reliabilityLabel {
    if (reliability >= 0.75) return 'Probablement fiable';
    if (reliability >= 0.45) return 'Fiabilité moyenne';
    return 'Peu fiable';
  }

  factory CommunityReport.fromJson(Map<String, dynamic> j) => CommunityReport(
        id: j['id'] as String,
        type: ReportType.fromName(j['type'] as String?),
        point: GeoPoint((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        expiresAt: DateTime.parse(j['expiresAt'] as String).toLocal(),
        status: (j['status'] as String?) ?? 'active',
        confirmations: (j['confirmations'] as num?)?.toInt() ?? 0,
        rejections: (j['rejections'] as num?)?.toInt() ?? 0,
        reliability: (j['reliability'] as num?)?.toDouble() ?? 0,
      );
}

/// Incident de circulation issu d'un fournisseur externe (via le backend).
class ExternalIncident {
  const ExternalIncident({
    required this.id,
    required this.category,
    required this.point,
    required this.source,
    this.description,
    this.delayMinutes,
    this.endTime,
  });

  final String id;
  final ReportType category;
  final GeoPoint point;
  final String source;
  final String? description;
  final int? delayMinutes;
  final DateTime? endTime;

  factory ExternalIncident.fromJson(Map<String, dynamic> j) => ExternalIncident(
        id: j['id'] as String,
        category: ReportType.fromName(j['category'] as String?),
        point: GeoPoint((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        source: (j['source'] as String?) ?? 'externe',
        description: j['description'] as String?,
        delayMinutes: (j['delayMinutes'] as num?)?.toInt(),
        endTime: j['endTime'] == null ? null : DateTime.tryParse(j['endTime'] as String)?.toLocal(),
      );
}

/// Instantané des informations routières d'une zone.
class TrafficSnapshot {
  const TrafficSnapshot({
    required this.reports,
    required this.incidents,
    required this.externalAvailable,
    required this.provider,
    required this.fetchedAt,
  });

  static const TrafficSnapshot empty = TrafficSnapshot(
    reports: [],
    incidents: [],
    externalAvailable: false,
    provider: null,
    fetchedAt: null,
  );

  final List<CommunityReport> reports;
  final List<ExternalIncident> incidents;

  /// Faux si aucun fournisseur de trafic n'est configuré côté serveur : on ne montre alors aucune donnée de trafic externe.
  final bool externalAvailable;
  final String? provider;
  final DateTime? fetchedAt;

  bool get isEmpty => reports.isEmpty && incidents.isEmpty;
}

/// Événement affichable sur la carte (signalement ou incident externe).
class MapEvent {
  const MapEvent({required this.id, required this.type, required this.point, this.report, this.incident});

  final String id;
  final ReportType type;
  final GeoPoint point;
  final CommunityReport? report;
  final ExternalIncident? incident;
}

/// Nombre d'événements connus à moins de `radiusM` mètres de l'itinéraire.
int countEventsNearRoute(List<GeoPoint> shape, Iterable<MapEvent> events, {double radiusM = 120}) {
  if (shape.length < 2) return 0;
  var n = 0;
  for (final e in events) {
    if (distanceToPolylineM(shape, e.point) <= radiusM) n++;
  }
  return n;
}
