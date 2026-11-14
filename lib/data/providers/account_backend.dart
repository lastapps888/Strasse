import 'package:strasse/core/core.dart';
import 'package:strasse/domain/domain.dart';

/// Résultat d'un signalement : créé ou fusionné avec un signalement existant (compté comme confirmation).
class ReportResult {
  const ReportResult(this.report, {required this.merged});
  final CommunityReport report;
  final bool merged;
}

/// Données échangées lors d'une synchronisation.
class SyncPayload {
  const SyncPayload({
    required this.serverTime,
    required this.favorites,
    required this.collections,
    required this.trips,
    required this.preferences,
    required this.preferencesUpdatedAt,
  });

  final DateTime serverTime;
  final List<Favorite> favorites;
  final List<PlaceCollection> collections;
  final List<PlannedTrip> trips;
  final Map<String, dynamic>? preferences;
  final DateTime? preferencesUpdatedAt;
}

/// Résultat des incidents de circulation externes.
typedef IncidentsResult = ({bool available, String? provider, List<ExternalIncident> incidents});

/// Contrat commun des backends facultatifs (serveur Strasse, Supabase) : compte, synchronisation, signalements.
/// L'application ne dépend que de cette interface : changer de backend ne change rien d'autre.
abstract class AccountBackend {
  /// Faux tant que le backend n'est pas configuré (aucune requête n'est alors envoyée).
  bool get configured;

  /// Nom affiché dans l'interface.
  String get label;

  /// Vrai si le backend sait envoyer un e-mail de réinitialisation de mot de passe.
  bool get supportsPasswordReset;

  Future<String> register(String email, String password);
  Future<String> login(String email, String password);
  Future<void> logout();
  Future<void> resetPassword(String email);
  Future<void> deleteAccount();

  Future<SyncPayload> pull({DateTime? since});
  Future<DateTime> push({
    required List<Favorite> favorites,
    required List<PlaceCollection> collections,
    required List<PlannedTrip> trips,
    Map<String, dynamic>? preferences,
    DateTime? preferencesUpdatedAt,
  });

  Future<List<CommunityReport>> reports(GeoBounds bounds);
  Future<ReportResult> createReport(ReportType type, GeoPoint p);
  Future<CommunityReport> confirmReport(String id);
  Future<CommunityReport> rejectReport(String id);

  Future<IncidentsResult> incidents(GeoBounds bounds);
}
