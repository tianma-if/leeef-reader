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

  test('mobile chrome starts hidden; desktop chrome starts visible', () {
    expect(readerChromeStartsVisible(TargetPlatform.android), isFalse);
    expect(readerChromeStartsVisible(TargetPlatform.iOS), isFalse);
    expect(readerChromeStartsVisible(TargetPlatform.macOS), isTrue);
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
