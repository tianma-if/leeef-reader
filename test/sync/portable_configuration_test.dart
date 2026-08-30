import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/sync/trusted/portable_configuration.dart';
import 'package:leeef_reader/src/sync/trusted/secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'pairing snapshot includes credentials and excludes local paths',
    () async {
      SharedPreferences.setMockInitialValues({
        'leeef.reader.font_size': 21.0,
        'leeef.appearance.theme_mode': 'dark',
        'leeef.sync.backend': 's3',
        'leeef.sync.s3.endpoint': 'https://s3.example.com',
        'leeef.storage.custom_directory': '/source/books',
        'leeef.window.width': 1400.0,
      });
      final sourcePreferences = await SharedPreferences.getInstance();
      final sourceSecrets = MemorySecretStore({
        'leeef.sync.s3.access_key_id': 'access',
        'leeef.sync.s3.secret_access_key': 'secret',
        'leeef.ai.api_key': 'ai-secret',
        'leeef.trusted.group_key': 'must-not-leak',
      });
      final source = PortableConfiguration(
        preferences: sourcePreferences,
        secrets: sourceSecrets,
        clock: () => DateTime.utc(2026, 8, 30),
      );
      final entries = await source.capture('source-device');

      expect(
        entries.map((entry) => entry.key),
        containsAll([
          'leeef.reader.font_size',
          'leeef.sync.s3.endpoint',
          'leeef.sync.s3.secret_access_key',
          'leeef.ai.api_key',
        ]),
      );
      expect(
        entries.map((entry) => entry.key),
        isNot(contains('leeef.storage.custom_directory')),
      );
      expect(
        entries.map((entry) => entry.key),
        isNot(contains('leeef.trusted.group_key')),
      );

      SharedPreferences.setMockInitialValues({
        'leeef.storage.custom_directory': '/target/books',
      });
      final targetPreferences = await SharedPreferences.getInstance();
      final targetSecrets = MemorySecretStore();
      final target = PortableConfiguration(
        preferences: targetPreferences,
        secrets: targetSecrets,
      );
      await target.applyPairingSnapshot(entries);

      expect(targetPreferences.getDouble('leeef.reader.font_size'), 21.0);
      expect(targetPreferences.getString('leeef.sync.backend'), 's3');
      expect(
        targetPreferences.getString('leeef.storage.custom_directory'),
        '/target/books',
      );
      expect(await targetSecrets.read('leeef.ai.api_key'), 'ai-secret');
      expect(
        await targetSecrets.read('leeef.sync.s3.secret_access_key'),
        'secret',
      );
    },
  );
}
