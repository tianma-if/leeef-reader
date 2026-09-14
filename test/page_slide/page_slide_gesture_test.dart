import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/page_slide/page_slide_gesture.dart';

void main() {
  test('finger travel maps 1:1 onto page width', () {
    expect(
      pageSlideProgressFromPointer(
        origin: const Offset(360, 400),
        current: const Offset(180, 400),
        width: 360,
        direction: 1,
      ),
      closeTo(0.5, 0.001),
    );
    expect(
      pageSlideProgressFromPointer(
        origin: const Offset(0, 400),
        current: const Offset(360, 400),
        width: 360,
        direction: -1,
      ),
      closeTo(1, 0.001),
    );
  });

  test('a quarter-page drag commits; a short nudge does not', () {
    expect(
      pageSlideShouldComplete(progress: 0.25, velocity: 0, alongPixels: 90),
      isTrue,
    );
    expect(
      pageSlideShouldComplete(progress: 0.05, velocity: 0, alongPixels: 16),
      isFalse,
    );
    expect(
      pageSlideShouldComplete(progress: 0.08, velocity: -500, alongPixels: 30),
      isTrue,
    );
  });

  test('swipe lanes stay wide enough for a slightly inner start', () {
    expect(pageSlideSwipeZoneRatio(0.28), 0.4);
    expect(pageSlideDirectionForX(x: 130, width: 360, tapZoneRatio: 0.28), -1);
    expect(pageSlideDirectionForX(x: 180, width: 360, tapZoneRatio: 0.28), 0);
    expect(pageSlideDirectionForX(x: 250, width: 360, tapZoneRatio: 0.28), 1);
  });

  test('release projects velocity over 240ms and commits past halfway', () {
    expect(
      pageSlideCommitProjected(progress: 0.4, velocityPxPerMs: 0.6, width: 360),
      isTrue,
    );
    expect(
      pageSlideCommitProjected(progress: 0.2, velocityPxPerMs: 0, width: 360),
      isFalse,
    );
    expect(pageSlideEaseOutQuad(0), 0);
    expect(pageSlideEaseOutQuad(1), 1);
    expect(pageSlideEaseOutQuad(0.5), closeTo(0.75, 0.001));
  });

  test('gesture update follows horizontal delta', () {
    final gesture = PageSlideGesture();
    expect(
      gesture.update(horizontalDelta: -180, width: 360),
      closeTo(0.5, 0.001),
    );
    gesture.reset();
    expect(gesture.progress, 0);
  });
}
