import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/sync/directory_sync_backend.dart';
import 'package:leeef_reader/src/sync/trusted/portable_configuration.dart';
import 'package:leeef_reader/src/sync/trusted/secret_store.dart';
import 'package:leeef_reader/src/sync/trusted/sync_space_store.dart';
import 'package:leeef_reader/src/sync/trusted/trusted_device.dart';
import 'package:leeef_reader/src/sync/trusted/trusted_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'two trusted devices converge settings and secure credentials',
    () async {
      final root = await Directory.systemTemp.createTemp('leeef-trusted-sync-');
      addTearDown(() => root.delete(recursive: true));
      final backend = DirectorySyncBackend(root);

      SharedPreferences.setMockInitialValues({
        'leeef.device_id': 'desktop-device',
        'leeef.reader.font_size': 22.0,
        'leeef.appearance.theme_mode': 'dark',
        'leeef.sync.backend': 's3',
        'leeef.sync.s3.endpoint': 'https://s3.example.com',
      });
      final desktopPreferences = await SharedPreferences.getInstance();
      final desktopSecrets = MemorySecretStore({
        'leeef.sync.s3.access_key_id': 'access',
        'leeef.sync.s3.secret_access_key': 'secret',
        'leeef.ai.api_key': 'ai-key',
      });
      final desktopSpaceStore = SyncSpaceStore(
        preferences: desktopPreferences,
        secrets: desktopSecrets,
        clock: () => DateTime.utc(2026, 8, 30, 10),
      );
      final space = await desktopSpaceStore.ensureSpace();
      await TrustedSyncService(
        spaceStore: desktopSpaceStore,
        configuration: PortableConfiguration(
          preferences: desktopPreferences,
          secrets: desktopSecrets,
          clock: () => DateTime.utc(2026, 8, 30, 10),
        ),
        clock: () => DateTime.utc(2026, 8, 30, 10),
      ).synchronize(backend);

      SharedPreferences.setMockInitialValues({
        'leeef.device_id': 'phone-device',
      });
      final phonePreferences = await SharedPreferences.getInstance();
      final phoneSecrets = MemorySecretStore();
      final phoneSpaceStore = SyncSpaceStore(
        preferences: phonePreferences,
        secrets: phoneSecrets,
        clock: () => DateTime.utc(2026, 8, 30, 11),
      );
      await phoneSpaceStore.saveSpace(
        SyncSpaceState(
          id: space.id,
          keyEpoch: space.keyEpoch,
          groupKey: space.groupKey,
        ),
      );
      final report = await TrustedSyncService(
        spaceStore: phoneSpaceStore,
        configuration: PortableConfiguration(
          preferences: phonePreferences,
          secrets: phoneSecrets,
          clock: () => DateTime.utc(2026, 8, 30, 11),
        ),
        clock: () => DateTime.utc(2026, 8, 30, 11),
      ).synchronize(backend);

      expect(report?.appliedConfigurationValues, greaterThan(0));
      expect(phonePreferences.getDouble('leeef.reader.font_size'), 22.0);
      expect(phonePreferences.getString('leeef.appearance.theme_mode'), 'dark');
      expect(await phoneSecrets.read('leeef.ai.api_key'), 'ai-key');
      expect(
        await phoneSecrets.read('leeef.sync.s3.secret_access_key'),
        'secret',
      );
      expect(
        (await phoneSpaceStore.loadDevices()).map((device) => device.id),
        containsAll(['desktop-device', 'phone-device']),
      );
    },
  );
}
