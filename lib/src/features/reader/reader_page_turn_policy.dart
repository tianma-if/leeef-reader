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

/// Stored `curl` values are treated as slide after the 3D effect was retired.
String normalizePageTurnEffect(String effect) =>
    effect == 'curl' ? 'slide' : effect;

bool usesDesktopClickSlide({required String flow, TargetPlatform? platform}) =>
    flow == 'paginated' && isDesktopReaderPlatform(platform);

/// Header/footer chrome starts hidden. Desktop keeps a pinned sidebar instead.
bool readerChromeStartsVisible([TargetPlatform? platform]) => false;

bool readerSidebarStartsVisible([TargetPlatform? platform]) =>
    isDesktopReaderPlatform(platform);

bool usesMobileInteractiveSlide({
  required String flow,
  required String configuredEffect,
  TargetPlatform? platform,
}) =>
    flow == 'paginated' &&
    !isDesktopReaderPlatform(platform) &&
    normalizePageTurnEffect(configuredEffect) == 'slide';

String effectivePageTurnEffect({
  required String flow,
  required String configuredEffect,
  TargetPlatform? platform,
}) {
  if (flow != 'paginated') return configuredEffect;
  if (isDesktopReaderPlatform(platform)) return 'slide';
  return normalizePageTurnEffect(configuredEffect);
}

/// Effect sent to foliate-js. Mobile paginated reading uses the engine's own
/// finger-following slide instead of a Flutter snapshot overlay.
String enginePageTurnEffect({
  required String flow,
  required String configuredEffect,
  TargetPlatform? platform,
}) =>
    effectivePageTurnEffect(
          flow: flow,
          configuredEffect: configuredEffect,
          platform: platform,
        ) ==
        'none'
    ? 'none'
    : 'slide';
