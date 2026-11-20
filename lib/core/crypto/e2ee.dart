import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

/// Chiffrement de bout en bout des données de compte.
///
/// Hiérarchie de clés (tout est calculé sur l'appareil ; le serveur ne reçoit que des valeurs opaques) :
///  - Mot de passe + e-mail --Argon2id--> 64 octets : `authKey` (envoyée au serveur à la place du mot de passe)
///    et `wrapKey` (ne quitte jamais l'appareil).
///  - Clé maître `MK` (32 octets aléatoires) : chiffre toutes les données. Elle est stockée sur le serveur
///    uniquement « enveloppée » (AES-256-GCM) par `wrapKey` et, séparément, par la clé de récupération.
///  - Clé de récupération : 20 octets aléatoires affichés à l'inscription ; seule façon de rouvrir les données
///    si le mot de passe est oublié. Perdue en même temps que le mot de passe, les données sont irrécupérables.
class E2ee {
  const E2ee._();

  static final _aes = AesGcm.with256bits();
  static final _rng = Random.secure();

  // Argon2id : paramètres minimaux recommandés par l'OWASP (19 Mio, 2 passes, 1 voie).
  static final _argon = Argon2id(memory: 19456, parallelism: 1, iterations: 2, hashLength: 64);
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static Uint8List randomBytes(int n) => Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

  static String b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');
  static Uint8List unb64(String s) => Uint8List.fromList(base64Url.decode(base64Url.normalize(s)));

  /// Identifiant de compte envoyé au serveur : condensé de l'e-mail (le serveur ne connaît pas l'adresse).
  static String emailId(String email) => hash.sha256.convert(utf8.encode('strasse-id|${email.trim().toLowerCase()}')).toString();

  /// Dérive `authKey` et `wrapKey` depuis le mot de passe.
  static Future<({String authKey, SecretKey wrapKey})> derivePassword(String email, String password) async {
    final salt = hash.sha256.convert(utf8.encode('strasse-salt-v1|${email.trim().toLowerCase()}')).bytes;
    final out = await (await _argon.deriveKeyFromPassword(password: password, nonce: salt)).extractBytes();
    return (authKey: b64(out.sublist(0, 32)), wrapKey: SecretKey(out.sublist(32, 64)));
  }

  /// Dérive les clés liées à la clé de récupération.
  static Future<({SecretKey wrapKey, String verifier})> deriveRecovery(String recoveryKey) async {
    final raw = _recoveryBytes(recoveryKey);
    final wrap = await _hkdf.deriveKey(secretKey: SecretKey(raw), info: utf8.encode('strasse-recovery-wrap'), nonce: const <int>[]);
    final ver = await _hkdf.deriveKey(secretKey: SecretKey(raw), info: utf8.encode('strasse-recovery-auth'), nonce: const <int>[]);
    return (wrapKey: wrap, verifier: b64(await ver.extractBytes()));
  }

  static Future<SecretKey> dataKey(Uint8List mk) => _hkdf.deriveKey(secretKey: SecretKey(mk), info: utf8.encode('strasse-data-v1'), nonce: const <int>[]);

  // ----------------------------------------------------------- Clé de récupération (Base32, groupes de 4)

  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// 20 octets aléatoires → 32 caractères Base32 présentés en 8 groupes de 4.
  static String newRecoveryKey() {
    final bytes = randomBytes(20);
    final sb = StringBuffer();
    var buffer = 0, bits = 0;
    for (final b in bytes) {
      buffer = ((buffer << 8) | b) & 0xFFFF;
      bits += 8;
      while (bits >= 5) {
        sb.write(_alphabet[(buffer >> (bits - 5)) & 31]);
        bits -= 5;
      }
    }
    final s = sb.toString();
    return [for (var i = 0; i < s.length; i += 4) s.substring(i, i + 4)].join('-');
  }

  static Uint8List _recoveryBytes(String key) {
    final clean = key.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');
    if (clean.length != 32) throw const FormatException('Clé de récupération invalide.');
    final out = <int>[];
    var buffer = 0, bits = 0;
    for (final ch in clean.split('')) {
      buffer = ((buffer << 5) | _alphabet.indexOf(ch)) & 0xFFFF;
      bits += 5;
      if (bits >= 8) {
        out.add((buffer >> (bits - 8)) & 255);
        bits -= 8;
      }
    }
    return Uint8List.fromList(out);
  }

  static bool isValidRecoveryKey(String key) {
    try {
      _recoveryBytes(key);
      return true;
    } on FormatException {
      return false;
    }
  }

  // ----------------------------------------------------------- AES-256-GCM

  /// Chiffre : `nonce(12) || texte chiffré || étiquette(16)`, en Base64 URL. [aad] lie le bloc à son emplacement.
  static Future<String> seal(SecretKey key, List<int> plain, String aad) async {
    final box = await _aes.encrypt(plain, secretKey: key, aad: utf8.encode(aad));
    return b64(box.concatenation());
  }

  /// Déchiffre ; lève une erreur d'authentification si la clé est mauvaise ou si le bloc a été modifié.
  static Future<Uint8List> open(SecretKey key, String sealed, String aad) async {
    final box = SecretBox.fromConcatenation(unb64(sealed), nonceLength: 12, macLength: 16);
    return Uint8List.fromList(await _aes.decrypt(box, secretKey: key, aad: utf8.encode(aad)));
  }
}
