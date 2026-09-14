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
        expect(
          usesMobileInteractiveSlide(
            flow: 'paginated',
            configuredEffect: configuredEffect,
            platform: platform,
          ),
          isFalse,
        );
      }
    }
  });

  test('mobile paginated readers treat retired curl as interactive slide', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      expect(
        effectivePageTurnEffect(
          flow: 'paginated',
          configuredEffect: 'curl',
          platform: platform,
        ),
        'slide',
      );
      expect(
        usesMobileInteractiveSlide(
          flow: 'paginated',
          configuredEffect: 'curl',
          platform: platform,
        ),
        isTrue,
      );
      expect(
        usesMobileInteractiveSlide(
          flow: 'paginated',
          configuredEffect: 'slide',
          platform: platform,
        ),
        isTrue,
      );
      expect(
        usesMobileInteractiveSlide(
          flow: 'paginated',
          configuredEffect: 'none',
          platform: platform,
        ),
        isFalse,
      );
      expect(
        enginePageTurnEffect(
          flow: 'paginated',
          configuredEffect: 'slide',
          platform: platform,
        ),
        'slide',
      );
    }
  });

  test('header and footer chrome start hidden on every platform', () {
    expect(readerChromeStartsVisible(TargetPlatform.android), isFalse);
    expect(readerChromeStartsVisible(TargetPlatform.iOS), isFalse);
    expect(readerChromeStartsVisible(TargetPlatform.macOS), isFalse);
  });

  test('desktop starts with a pinned sidebar; mobile does not', () {
    expect(readerSidebarStartsVisible(TargetPlatform.macOS), isTrue);
    expect(readerSidebarStartsVisible(TargetPlatform.windows), isTrue);
    expect(readerSidebarStartsVisible(TargetPlatform.android), isFalse);
    expect(readerSidebarStartsVisible(TargetPlatform.iOS), isFalse);
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
    expect(
      usesMobileInteractiveSlide(
        flow: 'scrolled',
        configuredEffect: 'slide',
        platform: TargetPlatform.iOS,
      ),
      isFalse,
    );
  });
}
