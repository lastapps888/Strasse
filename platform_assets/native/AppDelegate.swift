import Flutter
import AVFoundation
import MediaPlayer
import UIKit
import UserNotifications
#if canImport(MusicKit)
import MusicKit
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Affichage des notifications (téléchargements terminés, navigation) quand l'app est au premier plan.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Cycle de vie UIScene (Flutter 3.38+) : le FlutterViewController n'existe pas encore dans didFinishLaunching.
  // Plugins ET canaux natifs sont donc enregistrés ici, avec le messager du moteur implicite.
  // (L'ancien accès via window?.rootViewController renvoyait nil : aucun canal n'était créé, le changement d'icône échouait.)
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerStrasseChannels(messenger: engineBridge.applicationRegistrar.messenger())
  }

  // MARK: - Canaux natifs

  private func registerStrasseChannels(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "fr.strasse.strasse/icons", binaryMessenger: messenger).setMethodCallHandler { call, result in
      switch call.method {
      case "supported":
        result(UIApplication.shared.supportsAlternateIcons)
      case "current":
        // nil = icône principale.
        result(UIApplication.shared.alternateIconName)
      case "set":
        guard UIApplication.shared.supportsAlternateIcons else {
          result(FlutterError(code: "unsupported", message: "Les icônes alternatives ne sont pas prises en charge.", details: nil))
          return
        }
        let args = call.arguments as? [String: Any]
        let name = args?["name"] as? String
        // « default » = icône principale (nil pour iOS).
        let target: String? = (name == nil || name == "default") ? nil : name
        UIApplication.shared.setAlternateIconName(target) { error in
          if let error = error {
            result(FlutterError(code: "icon", message: error.localizedDescription, details: nil))
          } else {
            result(true)
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    FlutterMethodChannel(name: "fr.strasse.strasse/music", binaryMessenger: messenger).setMethodCallHandler { call, result in
      switch call.method {
      case "listTracks":
        DispatchQueue.global(qos: .userInitiated).async {
          let items = MPMediaQuery.songs().items ?? []
          var out: [[String: Any]] = []
          for item in items {
            // Les titres protégés (DRM / Apple Music) ou non téléchargés n'ont pas d'adresse de lecture.
            guard let url = item.assetURL else { continue }
            var track: [String: Any] = [
              "id": String(item.persistentID),
              "title": item.title ?? "",
              "artist": item.artist ?? "",
              "album": item.albumTitle ?? "",
              "durationMs": Int(item.playbackDuration * 1000),
              "uri": url.absoluteString,
            ]
            if let image = item.artwork?.image(at: CGSize(width: 256, height: 256)),
               let artwork = image.jpegData(compressionQuality: 0.82) {
              track["artwork"] = FlutterStandardTypedData(bytes: artwork)
            }
            out.append(track)
          }
          DispatchQueue.main.async { result(out) }
        }
      case "metadataForFile":
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String,
              !path.isEmpty else {
          result(FlutterError(code: "invalid", message: "Chemin du fichier manquant.", details: nil))
          return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          let asset = AVURLAsset(url: URL(fileURLWithPath: path))
          var metadata: [String: Any] = [:]
          for item in asset.commonMetadata {
            guard let key = item.commonKey else { continue }
            switch key {
            case .commonKeyTitle:
              if let value = item.stringValue, !value.isEmpty { metadata["title"] = value }
            case .commonKeyArtist:
              if let value = item.stringValue, !value.isEmpty { metadata["artist"] = value }
            case .commonKeyAlbumName:
              if let value = item.stringValue, !value.isEmpty { metadata["album"] = value }
            case .commonKeyArtwork:
              if let data = item.dataValue, let image = UIImage(data: data) {
                let maxDimension: CGFloat = 512
                let longest = max(image.size.width, image.size.height)
                let scale = longest > maxDimension ? maxDimension / longest : 1
                let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
                let renderer = UIGraphicsImageRenderer(size: size)
                let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                if let jpeg = resized.jpegData(compressionQuality: 0.84) {
                  metadata["artwork"] = FlutterStandardTypedData(bytes: jpeg)
                }
              }
            default:
              break
            }
          }
          let seconds = asset.duration.seconds
          if seconds.isFinite && seconds > 0 {
            metadata["durationMs"] = Int(seconds * 1000)
          }
          DispatchQueue.main.async { result(metadata) }
        }
      case "listPlaylists":
        DispatchQueue.global(qos: .userInitiated).async {
          let lists = MPMediaQuery.playlists().collections ?? []
          var out: [[String: Any]] = []
          for l in lists {
            out.append([
              "id": String(l.persistentID),
              "title": (l.value(forProperty: MPMediaPlaylistPropertyName) as? String) ?? "Playlist",
              "count": l.items.count,
            ])
          }
          DispatchQueue.main.async { result(out) }
        }
      case "playlistTracks":
        let id = (call.arguments as? [String: Any])?["id"] as? String
        DispatchQueue.global(qos: .userInitiated).async {
          var out: [[String: Any]] = []
          for l in MPMediaQuery.playlists().collections ?? [] where String(l.persistentID) == id {
            for item in l.items {
              guard let url = item.assetURL else { continue }
              var track: [String: Any] = [
                "id": String(item.persistentID), "title": item.title ?? "", "artist": item.artist ?? "",
                "album": item.albumTitle ?? "", "durationMs": Int(item.playbackDuration * 1000), "uri": url.absoluteString,
              ]
              if let image = item.artwork?.image(at: CGSize(width: 256, height: 256)),
                 let artwork = image.jpegData(compressionQuality: 0.82) {
                track["artwork"] = FlutterStandardTypedData(bytes: artwork)
              }
              out.append(track)
            }
          }
          DispatchQueue.main.async { result(out) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    #if canImport(MusicKit)
    if #available(iOS 15.0, *) {
      let bridge = MusicKitBridge()
      FlutterMethodChannel(name: "fr.strasse.strasse/applemusic", binaryMessenger: messenger).setMethodCallHandler { call, result in
        bridge.handle(call, result)
      }
    } else {
      FlutterMethodChannel(name: "fr.strasse.strasse/applemusic", binaryMessenger: messenger).setMethodCallHandler { _, result in
        result(FlutterError(code: "unsupported", message: "Apple Music nécessite iOS 15 ou plus récent.", details: nil))
      }
    }
    #else
    FlutterMethodChannel(name: "fr.strasse.strasse/applemusic", binaryMessenger: messenger).setMethodCallHandler { _, result in
      result(FlutterError(code: "unsupported", message: "MusicKit n'est pas disponible dans cette compilation.", details: nil))
    }
    #endif
  }
}

#if canImport(MusicKit)
/// Pont MusicKit : autorisation, recherche catalogue, bibliothèque (iOS 16+), lecture et état.
/// Nécessite le service « MusicKit » activé pour l'identifiant d'application (compte Apple Developer)
/// et un abonnement Apple Music pour la lecture.
@available(iOS 15.0, *)
final class MusicKitBridge {
  private let player = ApplicationMusicPlayer.shared

  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    Task { @MainActor in
      do {
        switch call.method {
        case "authorize":
          let status = await MusicAuthorization.request()
          result(status == .authorized ? "authorized" : String(describing: status))
        case "status":
          let status = MusicAuthorization.currentStatus
          let canPlay: Bool
          if status == .authorized {
            canPlay = try await MusicSubscription.current.canPlayCatalogContent
          } else {
            canPlay = false
          }
          result(["authorized": status == .authorized, "canPlay": canPlay])
        case "canPlay":
          let sub = try await MusicSubscription.current
          result(sub.canPlayCatalogContent)
        case "search":
          result(try await self.search(args["query"] as? String ?? ""))
        case "library":
          result(try await self.library(args["kind"] as? String ?? "playlist"))
        case "tracks":
          result(try await self.tracks(kind: args["kind"] as? String ?? "album", id: args["id"] as? String ?? "", library: args["library"] as? Bool ?? false))
        case "playSong":
          try await self.playSong(id: args["id"] as? String ?? "")
          result(true)
        case "playCollection":
          try await self.playCollection(kind: args["kind"] as? String ?? "album", id: args["id"] as? String ?? "", library: args["library"] as? Bool ?? false)
          result(true)
        case "play":
          try await self.player.play()
          result(true)
        case "pause":
          self.player.pause()
          result(true)
        case "next":
          try await self.player.skipToNextEntry()
          result(true)
        case "previous":
          try await self.player.skipToPreviousEntry()
          result(true)
        case "seek":
          self.player.playbackTime = TimeInterval((args["ms"] as? Int ?? 0)) / 1000.0
          result(true)
        case "shuffle":
          self.player.state.shuffleMode = (args["on"] as? Bool ?? false) ? .songs : .off
          result(true)
        case "repeat":
          switch args["mode"] as? String ?? "off" {
          case "all": self.player.state.repeatMode = .all
          case "one": self.player.state.repeatMode = .one
          default: self.player.state.repeatMode = MusicPlayer.RepeatMode.none
          }
          result(true)
        case "state":
          result(self.state())
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "musickit", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func art(_ a: Artwork?) -> String? { a?.url(width: 300, height: 300)?.absoluteString }

  private func songMap(_ s: Song) -> [String: Any?] {
    ["id": s.id.rawValue, "title": s.title, "artist": s.artistName, "album": s.albumTitle ?? "",
     "durationMs": Int((s.duration ?? 0) * 1000), "art": art(s.artwork)]
  }

  private func search(_ term: String) async throws -> [String: Any] {
    guard !term.isEmpty else { return ["tracks": [], "collections": []] }
    var req = MusicCatalogSearchRequest(term: term, types: [Song.self, Album.self, Artist.self, Playlist.self])
    req.limit = 20
    let res = try await req.response()
    var cols: [[String: Any?]] = []
    for a in res.albums { cols.append(["id": a.id.rawValue, "kind": "album", "title": a.title, "subtitle": a.artistName, "art": art(a.artwork)]) }
    for a in res.artists { cols.append(["id": a.id.rawValue, "kind": "artist", "title": a.name, "subtitle": "", "art": art(a.artwork)]) }
    for p in res.playlists { cols.append(["id": p.id.rawValue, "kind": "playlist", "title": p.name, "subtitle": "", "art": art(p.artwork)]) }
    return ["tracks": res.songs.map { songMap($0) }, "collections": cols]
  }

  private func library(_ kind: String) async throws -> [[String: Any?]] {
    guard #available(iOS 16.0, *) else {
      throw NSError(domain: "strasse", code: 1, userInfo: [NSLocalizedDescriptionKey: "La bibliothèque Apple Music nécessite iOS 16 ou plus récent."])
    }
    switch kind {
    case "album":
      let r = try await MusicLibraryRequest<Album>().response()
      return r.items.map { ["id": $0.id.rawValue, "kind": "album", "title": $0.title, "subtitle": $0.artistName, "art": art($0.artwork)] }
    case "artist":
      let r = try await MusicLibraryRequest<Artist>().response()
      return r.items.map { ["id": $0.id.rawValue, "kind": "artist", "title": $0.name, "subtitle": "", "art": art($0.artwork)] }
    default:
      let r = try await MusicLibraryRequest<Playlist>().response()
      return r.items.map { ["id": $0.id.rawValue, "kind": "playlist", "title": $0.name, "subtitle": "", "art": art($0.artwork)] }
    }
  }

  private func tracks(kind: String, id: String, library: Bool) async throws -> [[String: Any?]] {
    if kind == "album" {
      let album = try await fetchAlbum(id: id, library: library)
      return (album.tracks ?? []).map { t in ["id": t.id.rawValue, "title": t.title, "artist": t.artistName, "album": album.title, "durationMs": Int((t.duration ?? 0) * 1000), "art": art(album.artwork)] }
    }
    if kind == "playlist" {
      let pl = try await fetchPlaylist(id: id, library: library)
      return (pl.tracks ?? []).map { t in ["id": t.id.rawValue, "title": t.title, "artist": t.artistName, "album": "", "durationMs": Int((t.duration ?? 0) * 1000), "art": art(t.artwork)] }
    }
    return []
  }

  private func fetchAlbum(id: String, library: Bool) async throws -> Album {
    if library, #available(iOS 16.0, *) {
      var req = MusicLibraryRequest<Album>()
      req.filter(matching: \.id, equalTo: MusicItemID(id))
      if let a = try await req.response().items.first { return try await a.with([.tracks]) }
    }
    let req = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(id))
    guard let a = try await req.response().items.first else { throw NSError(domain: "strasse", code: 2, userInfo: [NSLocalizedDescriptionKey: "Album introuvable."]) }
    return try await a.with([.tracks])
  }

  private func fetchPlaylist(id: String, library: Bool) async throws -> Playlist {
    if library, #available(iOS 16.0, *) {
      var req = MusicLibraryRequest<Playlist>()
      req.filter(matching: \.id, equalTo: MusicItemID(id))
      if let p = try await req.response().items.first { return try await p.with([.tracks]) }
    }
    let req = MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: MusicItemID(id))
    guard let p = try await req.response().items.first else { throw NSError(domain: "strasse", code: 3, userInfo: [NSLocalizedDescriptionKey: "Playlist introuvable."]) }
    return try await p.with([.tracks])
  }

  private func playSong(id: String) async throws {
    let req = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
    guard let song = try await req.response().items.first else { throw NSError(domain: "strasse", code: 4, userInfo: [NSLocalizedDescriptionKey: "Titre introuvable dans le catalogue."]) }
    player.queue = [song]
    try await player.play()
  }

  private func playCollection(kind: String, id: String, library: Bool) async throws {
    switch kind {
    case "album":
      player.queue = [try await fetchAlbum(id: id, library: library)]
    case "playlist":
      player.queue = [try await fetchPlaylist(id: id, library: library)]
    case "artist":
      let req = MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: MusicItemID(id))
      guard let artist = try await req.response().items.first else { throw NSError(domain: "strasse", code: 5, userInfo: [NSLocalizedDescriptionKey: "Artiste introuvable."]) }
      let full = try await artist.with([.topSongs])
      guard let songs = full.topSongs, !songs.isEmpty else { throw NSError(domain: "strasse", code: 6, userInfo: [NSLocalizedDescriptionKey: "Aucun titre pour cet artiste."]) }
      player.queue = ApplicationMusicPlayer.Queue(for: songs)
    default:
      throw NSError(domain: "strasse", code: 7, userInfo: [NSLocalizedDescriptionKey: "Type de sélection non pris en charge."])
    }
    try await player.play()
  }

  private func state() -> [String: Any?] {
    let entry = player.queue.currentEntry
    var duration = 0
    if let item = entry?.item {
      switch item {
      case .song(let s): duration = Int((s.duration ?? 0) * 1000)
      default: break
      }
    }
    let rep: String
    switch player.state.repeatMode {
    case .some(.all): rep = "all"
    case .some(.one): rep = "one"
    default: rep = "off"
    }
    return [
      "playing": player.state.playbackStatus == .playing,
      "positionMs": Int(player.playbackTime * 1000),
      "durationMs": duration,
      "shuffle": (player.state.shuffleMode ?? .off) != .off,
      "repeat": rep,
      "title": entry?.title,
      "artist": entry?.subtitle,
      "art": art(entry?.artwork),
      "id": entry?.id,
    ]
  }
}
#endif
