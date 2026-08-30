import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:leeef_reader/src/sync/trusted/secret_store.dart';
import 'package:leeef_reader/src/sync/trusted/trusted_device.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class SyncSpaceStore {
  SyncSpaceStore({
    required this.preferences,
    required this.secrets,
    DateTime Function()? clock,
    Uuid uuid = const Uuid(),
  }) : _clock = clock ?? DateTime.now,
       _uuid = uuid;

  static const spaceIdKey = 'leeef.trusted.space_id';
  static const keyEpochKey = 'leeef.trusted.key_epoch';
  static const groupKeySecretKey = 'leeef.trusted.group_key';
  static const identityPrivateKey = 'leeef.trusted.identity_private_key';
  static const deviceNameKey = 'leeef.trusted.device_name';
  static const devicesCacheKey = 'leeef.trusted.devices_cache';

  final SharedPreferences preferences;
  final SecretStore secrets;
  final DateTime Function() _clock;
  final Uuid _uuid;
  final X25519 _keyExchange = X25519();
  final AesGcm _cipher = AesGcm.with256bits();

  Future<DeviceIdentity> loadOrCreateIdentity() async {
    var deviceId = preferences.getString('leeef.device_id');
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = _uuid.v7();
      await preferences.setString('leeef.device_id', deviceId);
    }
    final privateKey = await secrets.read(identityPrivateKey);
    late List<int> privateBytes;
    if (privateKey == null || privateKey.isEmpty) {
      privateBytes = await (await _keyExchange.newKeyPair())
          .extractPrivateKeyBytes();
      await secrets.write(identityPrivateKey, base64UrlEncode(privateBytes));
    } else {
      privateBytes = base64Url.decode(privateKey);
    }
    final keyPair = await _keyExchange.newKeyPairFromSeed(privateBytes);
    final publicKey = await keyPair.extractPublicKey();
    final now = _clock().toUtc();
    final cached = await loadDevices();
    final previous = cached.where((item) => item.id == deviceId).firstOrNull;
    final device = TrustedDevice(
      id: deviceId,
      name:
          preferences.getString(deviceNameKey) ??
          previous?.name ??
          '${_platformLabel()} · ${deviceId.substring(deviceId.length - 4)}',
      platform: Platform.operatingSystem,
      publicKey: base64UrlEncode(publicKey.bytes),
      addedAt: previous?.addedAt ?? now,
      lastSeenAt: now,
      revokedAt: previous?.revokedAt,
    );
    await upsertCachedDevice(device);
    return DeviceIdentity(device: device, privateKey: privateBytes);
  }

  Future<SyncSpaceState?> loadSpace() async {
    final id = preferences.getString(spaceIdKey);
    final encodedKey = await secrets.read(groupKeySecretKey);
    if (id == null || id.isEmpty || encodedKey == null || encodedKey.isEmpty) {
      return null;
    }
    return SyncSpaceState(
      id: id,
      keyEpoch: preferences.getInt(keyEpochKey) ?? 1,
      groupKey: base64Url.decode(encodedKey),
    );
  }

  Future<SyncSpaceState> ensureSpace() async {
    final existing = await loadSpace();
    if (existing != null) return existing;
    final groupKey = await (await _cipher.newSecretKey()).extractBytes();
    final state = SyncSpaceState(
      id: _uuid.v7(),
      keyEpoch: 1,
      groupKey: groupKey,
    );
    await saveSpace(state);
    return state;
  }

  Future<void> saveSpace(SyncSpaceState state) async {
    if (state.groupKey.length != 32) {
      throw ArgumentError('Sync group key must contain 32 bytes.');
    }
    await Future.wait([
      preferences.setString(spaceIdKey, state.id),
      preferences.setInt(keyEpochKey, state.keyEpoch),
      secrets.write(groupKeySecretKey, base64UrlEncode(state.groupKey)),
    ]);
  }

  Future<void> setDeviceName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Device name cannot be empty.');
    await preferences.setString(deviceNameKey, trimmed);
    final identity = await loadOrCreateIdentity();
    await upsertCachedDevice(identity.device.copyWith(name: trimmed));
  }

  Future<List<TrustedDevice>> loadDevices() async {
    final value = preferences.getString(devicesCacheKey);
    if (value == null || value.isEmpty) return const [];
    final decoded = jsonDecode(value);
    if (decoded is! List) return const [];
    final devices = decoded
        .whereType<Map>()
        .map((item) => TrustedDevice.fromJson(Map<String, Object?>.from(item)))
        .toList();
    devices.sort((left, right) {
      if (left.isRevoked != right.isRevoked) return left.isRevoked ? 1 : -1;
      return right.lastSeenAt.compareTo(left.lastSeenAt);
    });
    return devices;
  }

  Future<void> replaceCachedDevices(Iterable<TrustedDevice> devices) async {
    final byId = {for (final device in devices) device.id: device};
    await preferences.setString(
      devicesCacheKey,
      jsonEncode(byId.values.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> upsertCachedDevice(TrustedDevice device) async {
    final devices = {for (final item in await loadDevices()) item.id: item};
    devices[device.id] = device;
    await replaceCachedDevices(devices.values);
  }

  static String _platformLabel() => switch (Platform.operatingSystem) {
    'ios' => 'iPhone / iPad',
    'android' => 'Android',
    'macos' => 'Mac',
    'windows' => 'Windows PC',
    _ => Platform.operatingSystem,
  };
}
