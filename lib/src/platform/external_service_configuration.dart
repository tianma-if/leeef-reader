import 'package:flutter/foundation.dart';

/// Desktop is the configuration surface for third-party services: object
/// storage, WebDAV, AI/TTS credentials, HTTP proxies, and similar setup.
/// Mobile devices receive those settings by scanning a pairing QR code or
/// through trusted-device / cloud sync, and must not present credential or
/// provider entry UI.
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

String missingSyncBackendConfigurationMessage(
  String desktopMessage, [
  TargetPlatform? platform,
]) => allowsExternalServiceConfiguration(platform)
    ? desktopMessage
    : '请先在电脑上配置存储，并同步到此设备。';
