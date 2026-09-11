import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/platform/app_secure_storage.dart';

void main() {
  test('macOS secure storage avoids the Data Protection keychain', () {
    expect(
      appSecureStorage.mOptions.toMap()['usesDataProtectionKeychain'],
      'false',
    );
  });
}
