import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Shared Keychain/keystore access for credentials and device keys.
///
/// macOS `flutter_secure_storage` defaults to the Data Protection keychain,
/// which requires `keychain-access-groups`. Without that entitlement the
/// plugin fails with OSStatus -34018 ("A required entitlement is not present").
/// Use the file-based application keychain instead; it works for sandboxed
/// Developer ID builds and local ad-hoc debug runs.
const appSecureStorage = FlutterSecureStorage(
  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
);
