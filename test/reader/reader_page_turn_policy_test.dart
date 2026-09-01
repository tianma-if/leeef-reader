import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/features/reader/reader_page_turn_policy.dart';

void main() {
  test('desktop paginated readers always use click-triggered sliding', () {
    for (final platform in [
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    ]) {
      for (final configuredEffect in ['curl', 'none', 'slide']) {
        expect(
          effectivePageTurnEffect(
            flow: 'paginated',
            configuredEffect: configuredEffect,
            platform: platform,
          ),
          'slide',
        );
      }
    }
  });

  test('mobile readers preserve the configured page-turn effect', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      expect(
        effectivePageTurnEffect(
          flow: 'paginated',
          configuredEffect: 'curl',
          platform: platform,
        ),
        'curl',
      );
    }
  });

  test('continuous reading flow does not force a page transition', () {
    expect(
      effectivePageTurnEffect(
        flow: 'scrolled',
        configuredEffect: 'none',
        platform: TargetPlatform.macOS,
      ),
      'none',
    );
  });
}
