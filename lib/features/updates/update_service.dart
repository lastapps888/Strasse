import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:strasse/core/core.dart';

/// Version publiée sur les « Releases » GitHub officielles de Strasse.
class AppRelease {
  const AppRelease({required this.version, required this.tag, required this.notes, required this.pageUrl, this.publishedAt, this.apkUrl, this.apkName, this.apkSha256, this.apkSize, this.ipaUrl, this.ipaName});
  final String version;
  final String tag;
  final String notes;
  final String pageUrl;
  final DateTime? publishedAt;
  final String? apkUrl;
  final String? apkName;

  /// Empreinte SHA-256 publiée par GitHub pour le fichier (champ `digest` de l'asset), si disponible.
  final String? apkSha256;
  final int? apkSize;
  final String? ipaUrl;
  final String? ipaName;
}

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Compare deux numéros de version `1.2.3` (ignore un préfixe `v` et un suffixe `+build` / `-pre`). Retourne <0, 0 ou >0.
int compareVersions(String a, String b) {
  List<int> parse(String v) {
    final core = v.trim().replaceFirst(RegExp(r'^[vV]'), '').split(RegExp(r'[+\-]')).first;
    return [for (final p in core.split('.')) int.tryParse(p) ?? 0];
  }

  final x = parse(a), y = parse(b);
  for (var i = 0; i < 4; i++) {
    final xi = i < x.length ? x[i] : 0, yi = i < y.length ? y[i] : 0;
    if (xi != yi) return xi.compareTo(yi);
  }
  return 0;
}

/// Vérification et téléchargement des mises à jour depuis les Releases GitHub (API publique, sans compte ni clé).
/// Aucune donnée personnelle n'est envoyée : seule la requête HTTP elle-même (adresse IP) atteint GitHub.
class UpdateService {
  UpdateService({Dio? dio, String userAgent = ''})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 20),
              headers: {'Accept': 'application/vnd.github+json', if (userAgent.isNotEmpty) 'User-Agent': userAgent},
            ));

  final Dio _dio;
  static const _channel = MethodChannel('fr.strasse.strasse/update');

  static const latestUrl = 'https://api.github.com/repos/lastapps888/Strasse/releases/latest';

  Future<AppRelease?> latest() async {
    try {
      final r = await _dio.get<Map<String, dynamic>>(latestUrl);
      return parseRelease(r.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null; // aucune version publiée
      throw Failure.fromDio(e);
    }
  }

  static AppRelease? parseRelease(Map<String, dynamic>? j) {
    if (j == null || j['draft'] == true || j['prerelease'] == true) return null;
    final tag = '${j['tag_name'] ?? ''}';
    if (tag.isEmpty) return null;
    String? apkUrl, apkName, apkSha, ipaUrl, ipaName;
    int? apkSize;
    final assets = (j['assets'] as List?) ?? const [];
    for (final a in assets) {
      if (a is! Map) continue;
      final name = '${a['name'] ?? ''}';
      final url = '${a['browser_download_url'] ?? ''}';
      if (!url.startsWith('https://')) continue;
      if (name.toLowerCase().endsWith('.apk') && apkUrl == null) {
        apkUrl = url;
        apkName = name;
        apkSize = (a['size'] as num?)?.toInt();
        final d = '${a['digest'] ?? ''}';
        if (d.startsWith('sha256:')) apkSha = d.substring(7).toLowerCase();
      } else if (name.toLowerCase().endsWith('.ipa') && ipaUrl == null) {
        ipaUrl = url;
        ipaName = name;
      }
    }
    return AppRelease(
      version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      tag: tag,
      notes: '${j['body'] ?? ''}'.trim(),
      pageUrl: '${j['html_url'] ?? AppConfig.releasesUrl}',
      publishedAt: DateTime.tryParse('${j['published_at'] ?? ''}'),
      apkUrl: apkUrl,
      apkName: apkName,
      apkSha256: apkSha,
      apkSize: apkSize,
      ipaUrl: ipaUrl,
      ipaName: ipaName,
    );
  }

  Future<bool> canInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> openInstallSettings() async {
    try {
      await _channel.invokeMethod<bool>('openInstallSettings');
    } on PlatformException {
      // ignoré : l'utilisateur peut ouvrir le réglage lui-même
    }
  }

  /// Télécharge l'APK dans le cache de l'application, vérifie son empreinte SHA-256 (si GitHub en publie une) puis son
  /// signataire (même clé que l'application installée). Retourne le chemin du fichier vérifié.
  Future<String> downloadApk(AppRelease r, {void Function(double)? onProgress, CancelToken? cancel}) async {
    final url = r.apkUrl;
    if (url == null) throw const UpdateException('Cette version ne contient pas de fichier APK.');
    final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    await dir.create(recursive: true);
    final file = File('${dir.path}/Strasse-${r.version}.apk');
    try {
      await _dio.download(
        url,
        file.path,
        cancelToken: cancel,
        options: Options(receiveTimeout: const Duration(minutes: 10)),
        onReceiveProgress: (got, total) {
          if (total > 0) onProgress?.call(got / total);
        },
      );
    } on DioException catch (e) {
      if (file.existsSync()) file.deleteSync();
      if (CancelToken.isCancel(e)) throw const UpdateException('Téléchargement annulé.');
      throw UpdateException(Failure.fromDio(e).message);
    }
    if (r.apkSize != null && file.lengthSync() != r.apkSize) {
      file.deleteSync();
      throw const UpdateException('Fichier incomplet : téléchargement à recommencer.');
    }
    if (r.apkSha256 != null) {
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != r.apkSha256) {
        file.deleteSync();
        throw const UpdateException('Empreinte SHA-256 incorrecte : le fichier est corrompu ou altéré. Il a été supprimé.');
      }
    }
    bool same;
    try {
      same = await _channel.invokeMethod<bool>('sameSigner', {'path': file.path}) ?? false;
    } on PlatformException {
      same = false;
    }
    if (!same) {
      file.deleteSync();
      throw const UpdateException('Ce fichier n\'est pas signé par la même clé que votre Strasse : installation refusée.');
    }
    return file.path;
  }

  Future<void> install(String path) async {
    try {
      await _channel.invokeMethod<bool>('install', {'path': path});
    } on PlatformException catch (e) {
      throw UpdateException(e.message ?? 'Installation impossible.');
    }
  }
}
