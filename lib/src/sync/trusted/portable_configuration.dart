import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:leeef_reader/src/sync/trusted/secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ConfigurationScope { preference, secret }

class ConfigurationEntry {
  const ConfigurationEntry({
    required this.scope,
    required this.key,
    required this.value,
    required this.modifiedAt,
    required this.modifiedBy,
  });

  final ConfigurationScope scope;
  final String key;
  final Object? value;
  final DateTime modifiedAt;
  final String modifiedBy;

  String get identity => '${scope.name}:$key';

  Map<String, Object?> toJson() => {
    'scope': scope.name,
    'key': key,
    'value': value,
    'modifiedAt': modifiedAt.toUtc().toIso8601String(),
    'modifiedBy': modifiedBy,
  };

  factory ConfigurationEntry.fromJson(Map<String, Object?> json) =>
      ConfigurationEntry(
        scope: ConfigurationScope.values.byName(json['scope']! as String),
        key: json['key']! as String,
        value: json['value'],
        modifiedAt: DateTime.parse(json['modifiedAt']! as String).toUtc(),
        modifiedBy: json['modifiedBy']! as String,
      );
}

class PortableConfiguration {
  PortableConfiguration({
    required this.preferences,
    required this.secrets,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const _versionsKey = 'leeef.trusted.configuration_versions';

  final SharedPreferences preferences;
  final SecretStore secrets;
  final DateTime Function() _clock;

  Future<List<ConfigurationEntry>> capture(String deviceId) async {
    final values = await _readPortableValues();
    final versions = _readVersions();
    final now = _clock().toUtc();
    final identities = {...values.keys, ...versions.keys};
    final result = <ConfigurationEntry>[];
    for (final identity in identities) {
      final current = values[identity];
      final previous = versions[identity];
      if (current == null && previous == null) continue;
      final scope = ConfigurationScope.values.byName(
        identity.substring(0, identity.indexOf(':')),
      );
      final key = identity.substring(identity.indexOf(':') + 1);
      final value = current?.value;
      final digest = _digest(value);
      final changed = previous == null || previous.digest != digest;
      final entry = ConfigurationEntry(
        scope: scope,
        key: key,
        value: value,
        modifiedAt: changed ? now : previous.modifiedAt,
        modifiedBy: changed ? deviceId : previous.modifiedBy,
      );
      versions[identity] = _ConfigurationVersion(
        digest: digest,
        modifiedAt: entry.modifiedAt,
        modifiedBy: entry.modifiedBy,
      );
      result.add(entry);
    }
    await _saveVersions(versions);
    result.sort((left, right) => left.identity.compareTo(right.identity));
    return result;
  }

  Future<int> mergeAndApply(
    Iterable<ConfigurationEntry> candidates,
    String localDeviceId,
  ) async {
    final local = await capture(localDeviceId);
    final winners = <String, ConfigurationEntry>{
      for (final entry in local) entry.identity: entry,
    };
    for (final entry in candidates) {
      if (!_isPortable(entry.scope, entry.key)) continue;
      final current = winners[entry.identity];
      if (current == null || _compare(entry, current) > 0) {
        winners[entry.identity] = entry;
      }
    }

    final values = await _readPortableValues();
    final versions = _readVersions();
    var changed = 0;
    for (final entry in winners.values) {
      final current = values[entry.identity]?.value;
      if (_digest(current) != _digest(entry.value)) {
        await _write(entry);
        changed++;
      }
      versions[entry.identity] = _ConfigurationVersion(
        digest: _digest(entry.value),
        modifiedAt: entry.modifiedAt,
        modifiedBy: entry.modifiedBy,
      );
    }
    await _saveVersions(versions);
    return changed;
  }

  /// Applies a trusted pairing snapshot as the initial source of truth.
  Future<int> applyPairingSnapshot(Iterable<ConfigurationEntry> entries) async {
    final versions = _readVersions();
    var changed = 0;
    for (final entry in entries) {
      if (!_isPortable(entry.scope, entry.key)) continue;
      await _write(entry);
      versions[entry.identity] = _ConfigurationVersion(
        digest: _digest(entry.value),
        modifiedAt: entry.modifiedAt,
        modifiedBy: entry.modifiedBy,
      );
      changed++;
    }
    await _saveVersions(versions);
    return changed;
  }

  Future<Map<String, _PortableValue>> _readPortableValues() async {
    final result = <String, _PortableValue>{};
    for (final key in preferences.getKeys()) {
      if (!_isPortable(ConfigurationScope.preference, key)) continue;
      result['preference:$key'] = _PortableValue(preferences.get(key));
    }
    for (final entry in (await secrets.readAll()).entries) {
      if (!_isPortable(ConfigurationScope.secret, entry.key)) continue;
      result['secret:${entry.key}'] = _PortableValue(entry.value);
    }
    return result;
  }

  Future<void> _write(ConfigurationEntry entry) async {
    if (entry.scope == ConfigurationScope.secret) {
      final value = entry.value;
      if (value == null) {
        await secrets.delete(entry.key);
      } else if (value is String) {
        await secrets.write(entry.key, value);
      } else {
        throw const FormatException('Secure configuration must be a string.');
      }
      return;
    }
    final value = entry.value;
    if (value == null) {
      await preferences.remove(entry.key);
    } else if (value is bool) {
      await preferences.setBool(entry.key, value);
    } else if (value is int) {
      await preferences.setInt(entry.key, value);
    } else if (value is double) {
      await preferences.setDouble(entry.key, value);
    } else if (value is String) {
      await preferences.setString(entry.key, value);
    } else if (value is List) {
      await preferences.setStringList(
        entry.key,
        value.map((item) => item as String).toList(),
      );
    } else {
      throw FormatException('Unsupported preference ${entry.key}.');
    }
  }

  Map<String, _ConfigurationVersion> _readVersions() {
    final raw = preferences.getString(_versionsKey);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return decoded.map(
      (key, value) => MapEntry(
        key as String,
        _ConfigurationVersion.fromJson(Map<String, Object?>.from(value as Map)),
      ),
    );
  }

  Future<void> _saveVersions(Map<String, _ConfigurationVersion> versions) =>
      preferences.setString(
        _versionsKey,
        jsonEncode(versions.map((key, value) => MapEntry(key, value.toJson()))),
      );

  static bool _isPortable(ConfigurationScope scope, String key) {
    if (key.startsWith('leeef.trusted.') ||
        key == 'leeef.device_id' ||
        key.startsWith('leeef.window.') ||
        key.startsWith('leeef.storage.') ||
        key.startsWith('leeef.developer.') ||
        key.startsWith('leeef.ai.translation_cache') ||
        key == 'leeef.sync.directory' ||
        key == 'leeef.reader.background_image' ||
        key == 'leeef.reader.dark_background_image') {
      return false;
    }
    final prefixes = scope == ConfigurationScope.preference
        ? const [
            'leeef.reader.',
            'leeef.appearance.',
            'leeef.ai.',
            'leeef.tts.',
            'leeef.sync.',
            'leeef.opds.',
          ]
        : const [
            'leeef.ai.',
            'leeef.tts.',
            'leeef.sync.s3.',
            'leeef.sync.webdav.',
            'leeef.opds.password.',
          ];
    return prefixes.any(key.startsWith);
  }

  static int _compare(ConfigurationEntry left, ConfigurationEntry right) {
    final time = left.modifiedAt.compareTo(right.modifiedAt);
    return time != 0 ? time : left.modifiedBy.compareTo(right.modifiedBy);
  }

  static String _digest(Object? value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();
}

class _PortableValue {
  const _PortableValue(this.value);

  final Object? value;
}

class _ConfigurationVersion {
  const _ConfigurationVersion({
    required this.digest,
    required this.modifiedAt,
    required this.modifiedBy,
  });

  final String digest;
  final DateTime modifiedAt;
  final String modifiedBy;

  Map<String, Object?> toJson() => {
    'digest': digest,
    'modifiedAt': modifiedAt.toUtc().toIso8601String(),
    'modifiedBy': modifiedBy,
  };

  factory _ConfigurationVersion.fromJson(Map<String, Object?> json) =>
      _ConfigurationVersion(
        digest: json['digest']! as String,
        modifiedAt: DateTime.parse(json['modifiedAt']! as String).toUtc(),
        modifiedBy: json['modifiedBy']! as String,
      );
}
