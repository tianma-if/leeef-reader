import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/platform/external_service_configuration.dart';

void main() {
  test('desktop platforms keep AI and TTS credential configuration', () {
    for (final platform in [
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    ]) {
      expect(allowsExternalServiceConfiguration(platform), isTrue);
      expect(
        missingAiServiceConfigurationMessage(platform),
        '请先在设置中配置 AI 模型和 API Key。',
      );
    }
  });

  test('mobile platforms hide AI and TTS credential configuration', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      expect(allowsExternalServiceConfiguration(platform), isFalse);
      expect(
        missingAiServiceConfigurationMessage(platform),
        '请先在电脑上配置 AI，并同步到此设备。',
      );
      expect(
        missingSyncBackendConfigurationMessage('请先在设置中配置对象存储。', platform),
        '请先在电脑上配置存储，并同步到此设备。',
      );
    }
  });

  test('desktop platforms keep the original storage configuration errors', () {
    expect(
      missingSyncBackendConfigurationMessage(
        '请先在设置中配置对象存储。',
        TargetPlatform.macOS,
      ),
      '请先在设置中配置对象存储。',
    );
  });
}
