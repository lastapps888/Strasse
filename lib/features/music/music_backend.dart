import 'package:strasse/features/music/music_models.dart';

/// Contrat d'une source de musique. Les commandes non supportées lèvent [MusicException] ;
/// [capabilities] indique à l'interface lesquelles afficher.
abstract class MusicBackend {
  MusicSource get source;
  MusicCapabilities get capabilities;

  /// Vrai si la source peut fonctionner sur cette plateforme et avec cette configuration.
  Future<bool> isAvailable();

  /// Raison lisible si [isAvailable] est faux.
  Future<String?> unavailableReason();

  /// Connexion / autorisation. Retourne vrai si la source est prête.
  Future<bool> connect();
  bool get connected;
  Future<void> disconnect();

  /// État de lecture actuel (interrogé régulièrement par le contrôleur).
  Future<PlaybackSnapshot> snapshot();

  Future<void> play();
  Future<void> pause();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(int positionMs);
  Future<void> setVolume(double volume);
  Future<void> setShuffle(bool on);
  Future<void> setRepeat(PlayerRepeatMode mode);

  Future<MusicResults> search(String query);
  Future<List<MusicCollection>> library(CollectionKind kind);
  Future<List<MusicTrack>> tracksOf(MusicCollection c);

  Future<void> playTrack(MusicTrack t, {List<MusicTrack> queue = const []});
  Future<void> playCollection(MusicCollection c);

  void dispose();
}
