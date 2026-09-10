import 'package:flutter/foundation.dart';

/// Desktop is the configuration surface for third-party AI/TTS credentials.
/// Mobile devices receive those settings through trusted-device or cloud sync
/// and must not present API-key or provider entry UI.
bool allowsExternalServiceConfiguration([TargetPlatform? platform]) =>
    switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.iOS => false,
    };

String missingAiServiceConfigurationMessage([TargetPlatform? platform]) =>
    allowsExternalServiceConfiguration(platform)
    ? '请先在设置中配置 AI 模型和 API Key。'
    : '请先在电脑上配置 AI，并同步到此设备。';
