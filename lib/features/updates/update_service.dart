import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:strasse/core/core.dart';

/// Version publiée sur les « Releases » GitHub officielles de Strasse.
class AppRelease {
  const AppRelease({required this.version, required this.tag, required this.notes, required this.pageUrl, this.publishedAt, this.apkUrl, this.apkName, this.apkSha256, this.apkSize, this.ipaUrl, this.ipaName, this.ipaSha256, this.ipaSize, this.isPrerelease = false});
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
  final String? ipaSha256;
  final int? ipaSize;
  final bool isPrerelease;
}

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _ParsedVersion {
  const _ParsedVersion(this.major, this.minor, this.patch, this.prerelease);
  final int major;
  final int minor;
  final int patch;
  final List<String> prerelease;
  bool get isPrerelease => prerelease.isNotEmpty;
}

_ParsedVersion? _parseVersion(String input) {
  final value = input.trim().replaceFirst(RegExp(r'^[vV]'), '');
  final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$').firstMatch(value);
  if (match == null) return null;
  final prerelease = match.group(4);
  return _ParsedVersion(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    prerelease == null ? const [] : prerelease.split('.'),
  );
}

/// Compare deux versions SemVer 2.0.0 : une version stable est supérieure à ses préversions.
int compareVersions(String a, String b) {
  final x = _parseVersion(a);
  final y = _parseVersion(b);
  if (x == null || y == null) return a.compareTo(b);
  final core = [
    x.major.compareTo(y.major),
    x.minor.compareTo(y.minor),
    x.patch.compareTo(y.patch),
  ];
  for (final result in core) {
    if (result != 0) return result;
  }
  if (!x.isPrerelease && !y.isPrerelease) return 0;
  if (!x.isPrerelease) return 1;
  if (!y.isPrerelease) return -1;
  final length = x.prerelease.length < y.prerelease.length ? x.prerelease.length : y.prerelease.length;
  for (var i = 0; i < length; i++) {
    final left = x.prerelease[i];
    final right = y.prerelease[i];
    if (left == right) continue;
    final leftNumber = int.tryParse(left);
    final rightNumber = int.tryParse(right);
    if (leftNumber != null && rightNumber != null) return leftNumber.compareTo(rightNumber);
    if (leftNumber != null) return -1;
    if (rightNumber != null) return 1;
    return left.compareTo(right);
  }
  return x.prerelease.length.compareTo(y.prerelease.length);
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

  static const releasesUrl = 'https://api.github.com/repos/lastapps888/Strasse/releases?per_page=50';

  /// Les installations bêta reçoivent les préversions suivantes. Une installation stable ne bascule pas sur une bêta.
  Future<AppRelease?> latest({String installedVersion = ''}) async {
    try {
      final response = await _dio.get<List<dynamic>>(releasesUrl);
      final releases = <AppRelease>[];
      for (final raw in response.data ?? const []) {
        if (raw is! Map) continue;
        final release = parseRelease(Map<String, dynamic>.from(raw));
        if (release != null) releases.add(release);
      }
      if (releases.isEmpty) return null;
      final installedIsPrerelease = _parseVersion(installedVersion)?.isPrerelease ?? false;
      final candidates = releases.where((release) => installedIsPrerelease || !release.isPrerelease).toList();
      if (candidates.isEmpty) return null;
      candidates.sort((a, b) => compareVersions(b.version, a.version));
      return candidates.first;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw Failure.fromDio(e);
    }
  }
  static AppRelease? parseRelease(Map<String, dynamic>? j) {
    if (j == null || j['draft'] == true) return null;
    final tag = '${j['tag_name'] ?? ''}';
    if (tag.isEmpty) return null;
    String? apkUrl, apkName, apkSha, ipaUrl, ipaName, ipaSha;
    int? apkSize, ipaSize;
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
        ipaSize = (a['size'] as num?)?.toInt();
        final digestValue = a['digest'];
        final digest = digestValue is String ? digestValue : '';
        if (digest.startsWith('sha256:')) ipaSha = digest.substring(7).toLowerCase();
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
      ipaSha256: ipaSha,
      ipaSize: ipaSize,
      isPrerelease: j['prerelease'] == true || _parseVersion(tag.replaceFirst(RegExp(r'^[vV]'), ''))?.isPrerelease == true,
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

  /// Télécharge l'IPA dans Documents/Updates pour le rendre accessible via Fichiers.
  /// Vérifie taille et SHA-256 lorsque GitHub fournit ces informations. L'installation reste manuelle.
  Future<String> downloadIpa(AppRelease release, {void Function(double)? onProgress, CancelToken? cancel}) async {
    final url = release.ipaUrl;
    if (url == null) throw const UpdateException('Cette version ne contient pas de fichier IPA.');
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(documents.path + '/Updates');
    await directory.create(recursive: true);
    final safeVersion = release.version.replaceAll(RegExp(r'[^0-9A-Za-z.+_-]'), '_');
    final file = File(directory.path + '/Strasse-' + safeVersion + '.ipa');
    if (await file.exists()) await file.delete();
    try {
      await _dio.download(
        url,
        file.path,
        cancelToken: cancel,
        options: Options(receiveTimeout: const Duration(minutes: 10)),
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
      );
      if (release.ipaSize != null && await file.length() != release.ipaSize) {
        throw const UpdateException('Fichier IPA incomplet : relancez le téléchargement.');
      }
      if (release.ipaSha256 != null) {
        final digest = await sha256.bind(file.openRead()).first;
        if (digest.toString() != release.ipaSha256) {
          throw const UpdateException('Empreinte SHA-256 incorrecte : le fichier IPA a été supprimé.');
        }
      }
      return file.path;
    } on DioException catch (e) {
      if (await file.exists()) await file.delete();
      if (CancelToken.isCancel(e)) throw const UpdateException('Téléchargement annulé.');
      throw UpdateException(Failure.fromDio(e).message);
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  Future<void> install(String path) async {
    try {
      await _channel.invokeMethod<bool>('install', {'path': path});
    } on PlatformException catch (e) {
      throw UpdateException(e.message ?? 'Installation impossible.');
    }
  }
}
