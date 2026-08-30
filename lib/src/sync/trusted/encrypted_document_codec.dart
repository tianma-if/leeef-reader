import 'dart:convert';

import 'package:cryptography/cryptography.dart';

class EncryptedDocumentCodec {
  EncryptedDocumentCodec({AesGcm? cipher})
    : _cipher = cipher ?? AesGcm.with256bits();

  final AesGcm _cipher;

  Future<List<int>> encryptJson({
    required Map<String, Object?> value,
    required List<int> key,
    required String associatedData,
    required int keyEpoch,
  }) async {
    _validateKey(key);
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(value)),
      secretKey: SecretKey(key),
      aad: utf8.encode(associatedData),
    );
    return utf8.encode(
      jsonEncode({
        'version': 1,
        'algorithm': 'A256GCM',
        'keyEpoch': keyEpoch,
        'nonce': base64UrlEncode(box.nonce),
        'ciphertext': base64UrlEncode(box.cipherText),
        'mac': base64UrlEncode(box.mac.bytes),
      }),
    );
  }

  Future<Map<String, Object?>> decryptJson({
    required List<int> document,
    required List<int> key,
    required String associatedData,
    int? expectedKeyEpoch,
  }) async {
    _validateKey(key);
    final raw = jsonDecode(utf8.decode(document));
    if (raw is! Map) throw const FormatException('Invalid encrypted document.');
    final envelope = Map<String, Object?>.from(raw);
    if (envelope['version'] != 1 || envelope['algorithm'] != 'A256GCM') {
      throw const FormatException('Unsupported encrypted document.');
    }
    final epoch = envelope['keyEpoch'];
    if (epoch is! int ||
        (expectedKeyEpoch != null && epoch != expectedKeyEpoch)) {
      throw const FormatException('Unexpected encryption key epoch.');
    }
    final clearBytes = await _cipher.decrypt(
      SecretBox(
        base64Url.decode(envelope['ciphertext']! as String),
        nonce: base64Url.decode(envelope['nonce']! as String),
        mac: Mac(base64Url.decode(envelope['mac']! as String)),
      ),
      secretKey: SecretKey(key),
      aad: utf8.encode(associatedData),
    );
    final decoded = jsonDecode(utf8.decode(clearBytes));
    if (decoded is! Map) {
      throw const FormatException('Encrypted payload is not an object.');
    }
    return Map<String, Object?>.from(decoded);
  }

  static void _validateKey(List<int> key) {
    if (key.length != 32) {
      throw ArgumentError.value(key.length, 'key', 'Expected 32 bytes.');
    }
  }
}
