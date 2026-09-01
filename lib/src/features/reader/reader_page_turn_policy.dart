import 'package:flutter/foundation.dart';

bool isDesktopReaderPlatform([TargetPlatform? platform]) =>
    switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.iOS => false,
    };

bool usesDesktopClickSlide({required String flow, TargetPlatform? platform}) =>
    flow == 'paginated' && isDesktopReaderPlatform(platform);

String effectivePageTurnEffect({
  required String flow,
  required String configuredEffect,
  TargetPlatform? platform,
}) => usesDesktopClickSlide(flow: flow, platform: platform)
    ? 'slide'
    : configuredEffect;
