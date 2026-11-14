import 'package:strasse/core/core.dart';

enum OfflineStatus { downloading, complete, failed }

/// Région de carte téléchargée pour un usage hors connexion.
class OfflineRegionInfo {
  const OfflineRegionInfo({
    required this.id,
    required this.name,
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
    required this.status,
    required this.updatedAt,
    this.nativeId,
    this.sizeBytes = 0,
    this.requiredResources = 0,
    this.completedResources = 0,
    this.progress = 0,
    this.error,
  });

  final String id;
  final String name;
  final GeoBounds bounds;
  final int minZoom;
  final int maxZoom;
  final OfflineStatus status;
  final DateTime updatedAt;

  /// Identifiant de la région dans le moteur cartographique natif.
  final int? nativeId;
  final int sizeBytes;
  final int requiredResources;
  final int completedResources;

  /// 0..100
  final double progress;
  final String? error;

  bool get isComplete => status == OfflineStatus.complete;

  OfflineRegionInfo copyWith({
    OfflineStatus? status,
    int? nativeId,
    int? sizeBytes,
    int? requiredResources,
    int? completedResources,
    double? progress,
    String? error,
    DateTime? updatedAt,
    String? name,
  }) =>
      OfflineRegionInfo(
        id: id,
        name: name ?? this.name,
        bounds: bounds,
        minZoom: minZoom,
        maxZoom: maxZoom,
        status: status ?? this.status,
        updatedAt: updatedAt ?? this.updatedAt,
        nativeId: nativeId ?? this.nativeId,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        requiredResources: requiredResources ?? this.requiredResources,
        completedResources: completedResources ?? this.completedResources,
        progress: progress ?? this.progress,
        error: error ?? this.error,
      );
}
