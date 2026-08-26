import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:leeef_reader/src/ai/translation_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PersistentTranslationCache implements TranslationCache {
  const PersistentTranslationCache({this.maximumEntries = 300});
  static const _key = 'leeef.ai.translation_cache.v1';
  final int maximumEntries;

  static String digestKey(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  @override
  Future<String?> get(String key) async {
    final values = await _read();
    return values[digestKey(key)]?['value'] as String?;
  }

  @override
  Future<void> put(String key, String value) async {
    final preferences = await SharedPreferences.getInstance();
    final values = await _read();
    values[digestKey(key)] = {
      'value': value,
      'usedAt': DateTime.now().millisecondsSinceEpoch,
    };
    if (values.length > maximumEntries) {
      final ordered = values.entries.toList()
        ..sort(
          (a, b) =>
              (a.value['usedAt'] as int).compareTo(b.value['usedAt'] as int),
        );
      for (final entry in ordered.take(values.length - maximumEntries)) {
        values.remove(entry.key);
      }
    }
    await preferences.setString(_key, jsonEncode(values));
  }

  Future<Map<String, Map<String, Object?>>> _read() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map;
      return decoded.map(
        (key, value) =>
            MapEntry(key as String, Map<String, Object?>.from(value as Map)),
      );
    } on Object {
      return {};
    }
  }

  static Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(_key);
}
