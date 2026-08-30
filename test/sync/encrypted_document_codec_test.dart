import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/sync/trusted/encrypted_document_codec.dart';

void main() {
  test('encrypts authenticated JSON and rejects tampering', () async {
    final codec = EncryptedDocumentCodec();
    final key = List<int>.generate(32, (index) => index);
    final document = await codec.encryptJson(
      value: const {
        'apiKey': 'secret',
        'settings': {'theme': 'dark'},
      },
      key: key,
      associatedData: 'trusted/space/config/device.json',
      keyEpoch: 3,
    );

    final restored = await codec.decryptJson(
      document: document,
      key: key,
      associatedData: 'trusted/space/config/device.json',
      expectedKeyEpoch: 3,
    );
    expect(restored['apiKey'], 'secret');

    final envelope = Map<String, Object?>.from(
      jsonDecode(utf8.decode(document)) as Map,
    );
    final ciphertext = base64Url.decode(envelope['ciphertext']! as String);
    ciphertext[0] ^= 1;
    envelope['ciphertext'] = base64UrlEncode(ciphertext);
    await expectLater(
      codec.decryptJson(
        document: utf8.encode(jsonEncode(envelope)),
        key: key,
        associatedData: 'trusted/space/config/device.json',
        expectedKeyEpoch: 3,
      ),
      throwsA(anything),
    );
  });
}
