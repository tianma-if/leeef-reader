import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:leeef_reader/src/sync/sync_backend.dart';
import 'package:leeef_reader/src/sync/trusted/encrypted_document_codec.dart';
import 'package:leeef_reader/src/sync/trusted/portable_configuration.dart';
import 'package:leeef_reader/src/sync/trusted/secret_store.dart';
import 'package:leeef_reader/src/sync/trusted/sync_space_store.dart';
import 'package:leeef_reader/src/sync/trusted/trusted_device.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<TrustedSyncService> loadTrustedSyncService() async {
  final preferences = await SharedPreferences.getInstance();
  const secrets = FlutterSecretStore();
  return TrustedSyncService(
    spaceStore: SyncSpaceStore(preferences: preferences, secrets: secrets),
    configuration: PortableConfiguration(
      preferences: preferences,
      secrets: secrets,
    ),
  );
}

class TrustedSyncReport {
  const TrustedSyncReport({
    required this.appliedConfigurationValues,
    required this.deviceCount,
  });

  final int appliedConfigurationValues;
  final int deviceCount;
}

class TrustedSyncService {
  TrustedSyncService({
    required this.spaceStore,
    required this.configuration,
    EncryptedDocumentCodec? codec,
    DateTime Function()? clock,
  }) : _codec = codec ?? EncryptedDocumentCodec(),
       _clock = clock ?? DateTime.now;

  final SyncSpaceStore spaceStore;
  final PortableConfiguration configuration;
  final EncryptedDocumentCodec _codec;
  final DateTime Function() _clock;
  final X25519 _keyExchange = X25519();
  final Hkdf _kdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final AesGcm _cipher = AesGcm.with256bits();

  Future<TrustedSyncReport?> synchronize(SyncDocumentBackend backend) async {
    var space = await spaceStore.loadSpace();
    if (space == null) return null;
    final identity = await spaceStore.loadOrCreateIdentity();
    final base = 'trusted/${space.id}';

    space = await _applyKeyRotations(backend, space, identity, base);

    final revoked = await _loadRevocations(backend, space, base);
    if (revoked.containsKey(identity.device.id)) {
      throw StateError('当前设备已从同步设备中移除。');
    }

    final localDevice = identity.device.copyWith(lastSeenAt: _clock().toUtc());
    await _writeEncrypted(
      backend,
      space,
      '$base/devices/${localDevice.id}.json',
      localDevice.toJson(),
    );

    var localEntries = await configuration.capture(localDevice.id);
    await _writeConfiguration(
      backend,
      space,
      base,
      localDevice.id,
      localEntries,
    );

    final allEntries = <ConfigurationEntry>[...localEntries];
    for (final path in await backend.listDocuments('$base/config')) {
      final deviceId = _idFromPath(path);
      if (deviceId == null || revoked.containsKey(deviceId)) continue;
      final document = await backend.readDocument(path);
      if (document == null) continue;
      try {
        final payload = await _codec.decryptJson(
          document: document,
          key: space.groupKey,
          associatedData: path,
          expectedKeyEpoch: space.keyEpoch,
        );
        final entries = payload['entries'];
        if (entries is! List) continue;
        allEntries.addAll(
          entries.whereType<Map>().map(
            (item) =>
                ConfigurationEntry.fromJson(Map<String, Object?>.from(item)),
          ),
        );
      } on Object {
        // Documents from a stale key epoch are ignored until key rotation
        // support republishes them for the current epoch.
      }
    }
    final applied = await configuration.mergeAndApply(
      allEntries,
      localDevice.id,
    );
    localEntries = await configuration.capture(localDevice.id);
    await _writeConfiguration(
      backend,
      space,
      base,
      localDevice.id,
      localEntries,
    );

    final devices = <String, TrustedDevice>{};
    for (final path in await backend.listDocuments('$base/devices')) {
      final document = await backend.readDocument(path);
      if (document == null) continue;
      try {
        final payload = await _codec.decryptJson(
          document: document,
          key: space.groupKey,
          associatedData: path,
          expectedKeyEpoch: space.keyEpoch,
        );
        final device = TrustedDevice.fromJson(payload);
        devices[device.id] = revoked[device.id] == null
            ? device
            : device.copyWith(revokedAt: revoked[device.id]);
      } on Object {
        // A malformed device announcement cannot block other sync data.
      }
    }
    devices[localDevice.id] = localDevice;
    for (final cached in await spaceStore.loadDevices()) {
      devices.putIfAbsent(
        cached.id,
        () => revoked[cached.id] == null
            ? cached
            : cached.copyWith(revokedAt: revoked[cached.id]),
      );
    }
    await spaceStore.replaceCachedDevices(devices.values);
    return TrustedSyncReport(
      appliedConfigurationValues: applied,
      deviceCount: devices.values.where((item) => !item.isRevoked).length,
    );
  }

  Future<void> revokeDevice(
    SyncDocumentBackend backend,
    String deviceId,
  ) async {
    final space = await spaceStore.loadSpace();
    if (space == null) throw StateError('尚未建立同步设备空间。');
    final identity = await spaceStore.loadOrCreateIdentity();
    if (deviceId == identity.device.id) {
      throw ArgumentError('不能在当前设备上撤销当前设备。');
    }
    final revokedAt = _clock().toUtc();
    await _writeEncrypted(
      backend,
      space,
      'trusted/${space.id}/revocations/${space.keyEpoch}-$deviceId.json',
      {
        'deviceId': deviceId,
        'revokedAt': revokedAt.toIso8601String(),
        'revokedBy': identity.device.id,
      },
    );

    final devices = await spaceStore.loadDevices();
    final activeRecipients = devices.where(
      (device) => !device.isRevoked && device.id != deviceId,
    );
    final nextKey = await (await _cipher.newSecretKey()).extractBytes();
    final nextEpoch = space.keyEpoch + 1;
    final senderKeyPair = await _keyExchange.newKeyPairFromSeed(
      identity.privateKey,
    );
    final envelopes = <String, String>{};
    for (final recipient in activeRecipients) {
      final sharedSecret = await _keyExchange.sharedSecretKey(
        keyPair: senderKeyPair,
        remotePublicKey: SimplePublicKey(
          base64Url.decode(recipient.publicKey),
          type: KeyPairType.x25519,
        ),
      );
      final envelopeKey = await _deriveRotationKey(
        sharedSecret: sharedSecret,
        spaceId: space.id,
        epoch: nextEpoch,
        senderId: identity.device.id,
        recipientId: recipient.id,
      );
      final associatedData = _rotationEnvelopeAssociatedData(
        space.id,
        nextEpoch,
        identity.device.id,
        recipient.id,
      );
      envelopes[recipient.id] = base64UrlEncode(
        await _codec.encryptJson(
          value: {'groupKey': base64UrlEncode(nextKey)},
          key: envelopeKey,
          associatedData: associatedData,
          keyEpoch: nextEpoch,
        ),
      );
    }
    if (!envelopes.containsKey(identity.device.id)) {
      throw StateError('当前设备不在可信设备列表中。');
    }
    final rotation = <String, Object?>{
      'version': 1,
      'spaceId': space.id,
      'previousEpoch': space.keyEpoch,
      'epoch': nextEpoch,
      'senderId': identity.device.id,
      'senderPublicKey': identity.device.publicKey,
      'revokedDeviceId': deviceId,
      'createdAt': revokedAt.toIso8601String(),
      'envelopes': envelopes,
    };
    final authentication = _authenticateRotation(rotation, space.groupKey);
    final rotationCreated = await backend.writeDocumentIfAbsent(
      'trusted/${space.id}/keys/$nextEpoch.json',
      utf8.encode(jsonEncode({...rotation, 'authentication': authentication})),
    );
    if (!rotationCreated) {
      throw StateError('其他设备刚刚更新了设备列表，请同步后重试。');
    }

    final nextSpace = SyncSpaceState(
      id: space.id,
      keyEpoch: nextEpoch,
      groupKey: nextKey,
    );
    await spaceStore.saveSpace(nextSpace);
    await _writeEncrypted(
      backend,
      nextSpace,
      'trusted/${space.id}/revocations/$nextEpoch-$deviceId.json',
      {
        'deviceId': deviceId,
        'revokedAt': revokedAt.toIso8601String(),
        'revokedBy': identity.device.id,
      },
    );
    await spaceStore.replaceCachedDevices(
      devices.map(
        (device) => device.id == deviceId
            ? device.copyWith(revokedAt: revokedAt)
            : device,
      ),
    );
  }

  Future<SyncSpaceState> _applyKeyRotations(
    SyncDocumentBackend backend,
    SyncSpaceState initialSpace,
    DeviceIdentity identity,
    String base,
  ) async {
    var space = initialSpace;
    final paths = await backend.listDocuments('$base/keys');
    final rotations = <({int epoch, String path})>[];
    for (final path in paths) {
      final name = path.split('/').last;
      final epoch = int.tryParse(name.replaceFirst(RegExp(r'\.json$'), ''));
      if (epoch != null && epoch > space.keyEpoch) {
        rotations.add((epoch: epoch, path: path));
      }
    }
    rotations.sort((left, right) => left.epoch.compareTo(right.epoch));
    for (final item in rotations) {
      if (item.epoch != space.keyEpoch + 1) break;
      final bytes = await backend.readDocument(item.path);
      if (bytes == null) break;
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) throw const FormatException('Invalid key rotation.');
      final document = Map<String, Object?>.from(decoded);
      final authentication = document.remove('authentication');
      if (authentication is! String ||
          authentication != _authenticateRotation(document, space.groupKey) ||
          document['spaceId'] != space.id ||
          document['previousEpoch'] != space.keyEpoch ||
          document['epoch'] != item.epoch) {
        throw const FormatException('Key rotation authentication failed.');
      }
      if (document['revokedDeviceId'] == identity.device.id) {
        throw StateError('当前设备已从同步设备中移除。');
      }
      final envelopes = Map<String, Object?>.from(
        document['envelopes']! as Map,
      );
      final encodedEnvelope = envelopes[identity.device.id];
      if (encodedEnvelope is! String) {
        throw StateError('当前设备没有新同步密钥。');
      }
      final senderId = document['senderId']! as String;
      final sharedSecret = await _keyExchange.sharedSecretKey(
        keyPair: await _keyExchange.newKeyPairFromSeed(identity.privateKey),
        remotePublicKey: SimplePublicKey(
          base64Url.decode(document['senderPublicKey']! as String),
          type: KeyPairType.x25519,
        ),
      );
      final envelopeKey = await _deriveRotationKey(
        sharedSecret: sharedSecret,
        spaceId: space.id,
        epoch: item.epoch,
        senderId: senderId,
        recipientId: identity.device.id,
      );
      final payload = await _codec.decryptJson(
        document: base64Url.decode(encodedEnvelope),
        key: envelopeKey,
        associatedData: _rotationEnvelopeAssociatedData(
          space.id,
          item.epoch,
          senderId,
          identity.device.id,
        ),
        expectedKeyEpoch: item.epoch,
      );
      space = SyncSpaceState(
        id: space.id,
        keyEpoch: item.epoch,
        groupKey: base64Url.decode(payload['groupKey']! as String),
      );
      await spaceStore.saveSpace(space);
      final revokedId = document['revokedDeviceId']! as String;
      final revokedAt = DateTime.parse(
        document['createdAt']! as String,
      ).toUtc();
      await spaceStore.replaceCachedDevices(
        (await spaceStore.loadDevices()).map(
          (device) => device.id == revokedId
              ? device.copyWith(revokedAt: revokedAt)
              : device,
        ),
      );
    }
    return space;
  }

  Future<List<int>> _deriveRotationKey({
    required SecretKey sharedSecret,
    required String spaceId,
    required int epoch,
    required String senderId,
    required String recipientId,
  }) async => (await _kdf.deriveKey(
    secretKey: sharedSecret,
    nonce: utf8.encode(spaceId),
    info: utf8.encode('leeef-key-rotation-v1:$epoch:$senderId:$recipientId'),
  )).extractBytes();

  static String _rotationEnvelopeAssociatedData(
    String spaceId,
    int epoch,
    String senderId,
    String recipientId,
  ) => 'key-envelope:$spaceId:$epoch:$senderId:$recipientId';

  static String _authenticateRotation(
    Map<String, Object?> rotation,
    List<int> currentKey,
  ) => base64UrlEncode(
    crypto.Hmac(
      crypto.sha256,
      currentKey,
    ).convert(utf8.encode(jsonEncode(rotation))).bytes,
  );

  Future<Map<String, DateTime>> _loadRevocations(
    SyncDocumentBackend backend,
    SyncSpaceState space,
    String base,
  ) async {
    final result = <String, DateTime>{};
    for (final path in await backend.listDocuments('$base/revocations')) {
      final document = await backend.readDocument(path);
      if (document == null) continue;
      try {
        final payload = await _codec.decryptJson(
          document: document,
          key: space.groupKey,
          associatedData: path,
          expectedKeyEpoch: space.keyEpoch,
        );
        result[payload['deviceId']! as String] = DateTime.parse(
          payload['revokedAt']! as String,
        ).toUtc();
      } on Object {
        // Ignore corrupt or stale revocation records.
      }
    }
    return result;
  }

  Future<void> _writeConfiguration(
    SyncDocumentBackend backend,
    SyncSpaceState space,
    String base,
    String deviceId,
    List<ConfigurationEntry> entries,
  ) => _writeEncrypted(backend, space, '$base/config/$deviceId.json', {
    'deviceId': deviceId,
    'generatedAt': _clock().toUtc().toIso8601String(),
    'entries': entries.map((item) => item.toJson()).toList(),
  });

  Future<void> _writeEncrypted(
    SyncDocumentBackend backend,
    SyncSpaceState space,
    String path,
    Map<String, Object?> value,
  ) async {
    await backend.writeDocument(
      path,
      await _codec.encryptJson(
        value: value,
        key: space.groupKey,
        associatedData: path,
        keyEpoch: space.keyEpoch,
      ),
    );
  }

  static String? _idFromPath(String path) {
    final name = path.split('/').last;
    return name.endsWith('.json')
        ? name.substring(0, name.length - '.json'.length)
        : null;
  }
}
