import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/sync/directory_sync_backend.dart';
import 'package:leeef_reader/src/sync/trusted/pairing_service.dart';
import 'package:leeef_reader/src/sync/trusted/portable_configuration.dart';
import 'package:leeef_reader/src/sync/trusted/secret_store.dart';
import 'package:leeef_reader/src/sync/trusted/sync_space_store.dart';
import 'package:leeef_reader/src/sync/trusted/trusted_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('one-time LAN pairing restores configuration and credentials', () async {
    SharedPreferences.setMockInitialValues({
      'leeef.device_id': 'desktop-device',
      'leeef.reader.font_size': 23.0,
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
    );
    final desktopPairing = PairingService(
      spaceStore: desktopSpaceStore,
      configuration: PortableConfiguration(
        preferences: desktopPreferences,
        secrets: desktopSecrets,
      ),
    );
    final host = await desktopPairing.startHost();
    addTearDown(host.close);

    SharedPreferences.setMockInitialValues({'leeef.device_id': 'phone-device'});
    final phonePreferences = await SharedPreferences.getInstance();
    final phoneSecrets = MemorySecretStore();
    final phoneSpaceStore = SyncSpaceStore(
      preferences: phonePreferences,
      secrets: phoneSecrets,
    );
    final phonePairing = PairingService(
      spaceStore: phoneSpaceStore,
      configuration: PortableConfiguration(
        preferences: phonePreferences,
        secrets: phoneSecrets,
      ),
    );

    final result = await phonePairing.join(
      host.code,
      timeout: const Duration(seconds: 5),
    );
    final pairedDevice = await host.completion;

    expect(pairedDevice.id, 'phone-device');
    expect(result.space.id, isNotEmpty);
    expect(phonePreferences.getDouble('leeef.reader.font_size'), 23.0);
    expect(await phoneSecrets.read('leeef.ai.api_key'), 'ai-key');
    expect(
      await phoneSecrets.read('leeef.sync.s3.secret_access_key'),
      'secret',
    );
    expect(
      (await phoneSpaceStore.loadDevices()).map((device) => device.id),
      containsAll(['desktop-device', 'phone-device']),
    );
  });

  test('revoking a paired device rotates the group key', () async {
    final root = await Directory.systemTemp.createTemp('leeef-key-rotation-');
    addTearDown(() => root.delete(recursive: true));
    final backend = DirectorySyncBackend(root);

    SharedPreferences.setMockInitialValues({
      'leeef.device_id': 'desktop-device',
      'leeef.reader.font_size': 20.0,
    });
    final desktopPreferences = await SharedPreferences.getInstance();
    final desktopSecrets = MemorySecretStore();
    final desktopSpaceStore = SyncSpaceStore(
      preferences: desktopPreferences,
      secrets: desktopSecrets,
    );
    final desktopConfiguration = PortableConfiguration(
      preferences: desktopPreferences,
      secrets: desktopSecrets,
    );
    final host = await PairingService(
      spaceStore: desktopSpaceStore,
      configuration: desktopConfiguration,
    ).startHost();
    addTearDown(host.close);

    SharedPreferences.setMockInitialValues({'leeef.device_id': 'phone-device'});
    final phonePreferences = await SharedPreferences.getInstance();
    final phoneSecrets = MemorySecretStore();
    final phoneSpaceStore = SyncSpaceStore(
      preferences: phonePreferences,
      secrets: phoneSecrets,
    );
    final phoneConfiguration = PortableConfiguration(
      preferences: phonePreferences,
      secrets: phoneSecrets,
    );
    await PairingService(
      spaceStore: phoneSpaceStore,
      configuration: phoneConfiguration,
    ).join(host.code, timeout: const Duration(seconds: 5));
    await host.completion;

    final desktopSync = TrustedSyncService(
      spaceStore: desktopSpaceStore,
      configuration: desktopConfiguration,
    );
    final phoneSync = TrustedSyncService(
      spaceStore: phoneSpaceStore,
      configuration: phoneConfiguration,
    );
    await desktopSync.synchronize(backend);
    await phoneSync.synchronize(backend);

    await desktopSync.revokeDevice(backend, 'phone-device');
    expect((await desktopSpaceStore.loadSpace())?.keyEpoch, 2);
    expect((await phoneSpaceStore.loadSpace())?.keyEpoch, 1);
    await expectLater(
      phoneSync.synchronize(backend),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('移除'),
        ),
      ),
    );
  });
}
