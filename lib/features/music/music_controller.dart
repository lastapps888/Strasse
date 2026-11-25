import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/features/music/apple_music_backend.dart';
import 'package:strasse/features/music/audio_engine.dart';
import 'package:strasse/features/music/deezer_backend.dart';
import 'package:strasse/features/music/local_music_backend.dart';
import 'package:strasse/features/music/music_backend.dart';
import 'package:strasse/features/music/music_models.dart';
import 'package:strasse/features/music/spotify_backend.dart';
import 'package:strasse/features/services/provider_models.dart';

/// Les quatre sources, créées à la demande. Le lecteur interne (just_audio) n'est créé que si Deezer ou la musique locale sont utilisés.
class MusicBackends {
  MusicBackends(this._create);
  final MusicBackend Function(MusicSource source, AudioEngine Function() engine) _create;
  final Map<MusicSource, MusicBackend> _cache = {};
  AudioEngine? _engine;

  AudioEngine _getEngine() => _engine ??= AudioEngine();

  MusicBackend of(MusicSource s) => _cache.putIfAbsent(s, () => _create(s, _getEngine));

  Future<void> dispose() async {
    for (final b in _cache.values) {
      b.dispose();
    }
    await _engine?.dispose();
  }
}

final musicBackendsProvider = Provider<MusicBackends>((ref) {
  final r = ref.watch(providerResolverProvider);
  final secure = ref.watch(secureStoreProvider);
  final b = MusicBackends((source, engine) {
    switch (source) {
      case MusicSource.spotify:
        return SpotifyBackend(clientId: r.credential(r.selected(ServiceCategory.spotify), 'clientId'), secure: secure);
      case MusicSource.appleMusic:
        return AppleMusicBackend();
      case MusicSource.deezer:
        return DeezerBackend(baseUrl: r.urlOf(r.selected(ServiceCategory.deezer)), engine: engine(), userAgent: r.config.userAgent);
      case MusicSource.local:
        return LocalMusicBackend(engine: engine());
    }
  });
  ref.onDispose(b.dispose);
  return b;
});

class MusicState {
  const MusicState({
    this.source,
    this.connected = false,
    this.catalogAvailable = false,
    this.busy = false,
    this.snapshot = PlaybackSnapshot.idle,
    this.snapshotAt,
    this.error,
    this.needsLogin = false,
    this.unavailable,
    this.availability = const {},
  });

  final MusicSource? source;
  /// Catalogue public consultable sans authentification ni lecture active.
  final bool catalogAvailable;
  final bool connected;
  final bool busy;
  final PlaybackSnapshot snapshot;
  final DateTime? snapshotAt;
  final String? error;
  final bool needsLogin;

  /// Raison pour laquelle la source choisie est inutilisable (plateforme, configuration).
  final String? unavailable;

  /// Disponibilité de chaque source (null = disponible, texte = raison).
  final Map<MusicSource, String?> availability;

  /// Position estimée entre deux relevés (le relevé n'est pas continu pour Spotify et Apple Music).
  int positionNow(DateTime now) {
    final at = snapshotAt;
    if (at == null || !snapshot.playing) return snapshot.positionMs;
    final p = snapshot.positionMs + now.difference(at).inMilliseconds;
    return snapshot.durationMs > 0 ? p.clamp(0, snapshot.durationMs) : p;
  }

  MusicState copyWith({
    MusicSource? source,
    bool clearSource = false,
    bool? connected,
    bool? catalogAvailable,
    bool? busy,
    PlaybackSnapshot? snapshot,
    DateTime? snapshotAt,
    String? error,
    bool clearError = false,
    bool? needsLogin,
    String? unavailable,
    bool clearUnavailable = false,
    Map<MusicSource, String?>? availability,
  }) =>
      MusicState(
        source: clearSource ? null : (source ?? this.source),
        connected: connected ?? this.connected,
        catalogAvailable: catalogAvailable ?? this.catalogAvailable,
        busy: busy ?? this.busy,
        snapshot: snapshot ?? this.snapshot,
        snapshotAt: snapshotAt ?? this.snapshotAt,
        error: clearError ? null : (error ?? this.error),
        needsLogin: needsLogin ?? (clearError ? false : this.needsLogin),
        unavailable: clearUnavailable ? null : (unavailable ?? this.unavailable),
        availability: availability ?? this.availability,
      );
}

/// Pilote la source choisie : connexion, relevé régulier de l'état de lecture, commandes. Toutes les erreurs sont
/// converties en messages affichables : une source en panne ne bloque jamais le reste de l'application.
class MusicController extends StateNotifier<MusicState> {
  MusicController(this._ref) : super(const MusicState());

  final Ref _ref;
  Timer? _timer;
  int _watchers = 0;
  bool _polling = false;

  MusicBackends get _backends => _ref.read(musicBackendsProvider);
  MusicBackend? get backend => state.source == null ? null : _backends.of(state.source!);

  /// Initialise la source mémorisée et la disponibilité de toutes les sources.
  Future<void> init() async {
    final saved = MusicSource.fromName(_ref.read(settingsProvider).musicSource);
    final avail = <MusicSource, String?>{};
    for (final s in MusicSource.values) {
      final b = _backends.of(s);
      avail[s] = await b.isAvailable() ? null : await b.unavailableReason();
    }
    state = state.copyWith(availability: avail);
    if (saved != null && avail[saved] == null) await select(saved, connect: false);
  }

  Future<void> select(MusicSource s, {bool connect = true}) async {
    if (state.source == s) return;
    _timer?.cancel();
    final b = _backends.of(s);
    final reason = await b.unavailableReason();
    state = MusicState(
      source: s,
      availability: state.availability,
      unavailable: reason,
      connected: b.connected,
      catalogAvailable: s == MusicSource.deezer && reason == null,
    );
    await _ref.read(settingsProvider.notifier).update((x) => x.copyWith(musicSource: s.name));
    if (reason != null) return;
    // Spotify : restaure la session mémorisée sans rien demander.
    if (b is SpotifyBackend && await b.restore()) state = state.copyWith(connected: true);
    // Apple Music : relit l'autorisation système déjà donnée et le statut d'abonnement, sans nouvel écran.
    if (b is AppleMusicBackend && await b.restore()) state = state.copyWith(connected: true);
    // Musique locale : restaure les fichiers importés et relit les permissions déjà accordées,
    // sans redemander l'accès à chaque ouverture de Strasse.
    if (b is LocalMusicBackend && await b.restore()) state = state.copyWith(connected: true);
    if (connect && !state.connected && s != MusicSource.spotify && s != MusicSource.appleMusic && s != MusicSource.deezer) await this.connect();
    if (state.connected) _startTimer();
  }

  Future<bool> _guard(Future<void> Function() run) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      await run();
      state = state.copyWith(busy: false);
      return true;
    } on MusicException catch (e) {
      state = state.copyWith(busy: false, error: e.message, needsLogin: e.needsLogin, connected: e.needsLogin ? false : state.connected);
      return false;
    } catch (e) {
      state = state.copyWith(busy: false, error: 'Erreur inattendue de la source musicale.');
      return false;
    }
  }

  Future<void> connect() async {
    final b = backend;
    if (b == null) return;
    final ok = await _guard(() async {
      final ok = await b.connect();
      state = state.copyWith(connected: ok);
    });
    if (ok && state.connected) {
      _startTimer();
      await refresh();
    }
  }

  Future<void> disconnect() async {
    final b = backend;
    if (b == null) return;
    _timer?.cancel();
    await b.disconnect();
    state = state.copyWith(connected: false, snapshot: PlaybackSnapshot.idle);
  }

  // ------------------------------------------------------------- Relevé

  /// L'écran Musique et le mini-lecteur s'abonnent : le relevé n'a lieu que lorsqu'au moins l'un d'eux est visible.
  void watch() {
    _watchers++;
    if (state.connected) _startTimer();
  }

  void unwatch() {
    _watchers = (_watchers - 1).clamp(0, 1 << 20);
    if (_watchers == 0) _timer?.cancel();
  }

  void _startTimer() {
    _timer?.cancel();
    if (_watchers == 0) return;
    final fast = state.source == MusicSource.deezer || state.source == MusicSource.local;
    _timer = Timer.periodic(fast ? const Duration(milliseconds: 500) : const Duration(seconds: 2), (_) => refresh());
  }

  Future<void> refresh() async {
    final b = backend;
    if (b == null || !state.connected || _polling) return;
    _polling = true;
    try {
      final snap = await b.snapshot();
      if (mounted) state = state.copyWith(snapshot: snap, snapshotAt: DateTime.now(), clearError: state.error != null && !state.needsLogin);
    } on MusicException catch (e) {
      // Les relevés ne remplacent pas une erreur de commande plus utile ; Spotify sans appareil actif est un cas normal.
      if (mounted && e.needsLogin) state = state.copyWith(error: e.message, needsLogin: true, connected: false);
    } catch (_) {
      // relevé raté : on garde le dernier état connu
    } finally {
      _polling = false;
    }
  }

  // ----------------------------------------------------------- Commandes

  Future<void> _command(Future<void> Function(MusicBackend b) f) async {
    final b = backend;
    if (b == null) return;
    final succeeded = await _guard(() => f(b));
    // Deezer has no account session: connected tracks only an actually started preview player.
    if (succeeded && state.source == MusicSource.deezer && b.connected) {
      state = state.copyWith(connected: true);
      _startTimer();
    }
    await refresh();
  }

  Future<void> togglePlay() => _command((b) => state.snapshot.playing ? b.pause() : b.play());
  Future<void> next() => _command((b) => b.next());
  Future<void> previous() => _command((b) => b.previous());
  Future<void> seek(int ms) => _command((b) => b.seek(ms));
  Future<void> setVolume(double v) => _command((b) => b.setVolume(v));
  Future<void> toggleShuffle() => _command((b) => b.setShuffle(!state.snapshot.shuffle));
  Future<void> cycleRepeat() => _command((b) => b.setRepeat(state.snapshot.repeat.next));
  Future<void> playTrack(MusicTrack t, {List<MusicTrack> queue = const []}) => _command((b) => b.playTrack(t, queue: queue));
  Future<void> playCollection(MusicCollection c) => _command((b) => b.playCollection(c));

  /// Recherche et navigation : retournent aussi les erreurs à l'appelant via l'état.
  Future<MusicResults> search(String q) async {
    final b = backend;
    var out = const MusicResults();
    if (b == null) return out;
    await _guard(() async => out = await b.search(q));
    return out;
  }

  Future<List<MusicCollection>> library(CollectionKind k) async {
    final b = backend;
    var out = const <MusicCollection>[];
    if (b == null) return out;
    await _guard(() async => out = await b.library(k));
    return out;
  }

  Future<List<MusicTrack>> tracksOf(MusicCollection c) async {
    final b = backend;
    var out = const <MusicTrack>[];
    if (b == null) return out;
    await _guard(() async => out = await b.tracksOf(c));
    return out;
  }

  Future<int> pickLocalFiles() async {
    final b = backend;
    if (b is! LocalMusicBackend) return 0;
    var n = 0;
    await _guard(() async => n = await b.pickFiles());
    if (n > 0) {
      state = state.copyWith(connected: true);
      _startTimer();
    }
    return n;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final musicProvider = StateNotifierProvider<MusicController, MusicState>((ref) => MusicController(ref));
