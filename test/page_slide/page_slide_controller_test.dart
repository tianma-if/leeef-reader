import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/page_slide/page_slide_controller.dart';
import 'package:leeef_reader/src/page_slide/page_slide_gesture.dart';

void main() {
  test('pressing the edge does not pre-shift the page', () {
    final controller = PageSlideController()
      ..begin(
        position: const Offset(900, 800),
        size: const Size(1000, 1600),
        direction: 1,
      );
    addTearDown(controller.dispose);

    expect(controller.progress, 0);
  });

  test('forward and backward drags map to the same slide progress', () {
    final forward = PageSlideController()
      ..begin(
        position: const Offset(900, 800),
        size: const Size(1000, 1600),
        direction: 1,
      )
      ..update(const Offset(400, 800));
    final backward = PageSlideController()
      ..begin(
        position: const Offset(100, 800),
        size: const Size(1000, 1600),
        direction: -1,
      )
      ..update(const Offset(600, 800));
    addTearDown(forward.dispose);
    addTearDown(backward.dispose);

    expect(forward.progress, closeTo(backward.progress, 0.001));
    expect(forward.progress, closeTo(0.5, 0.001));
  });

  test('release survives snapshot delay before surface attaches', () async {
    final controller = PageSlideController()
      ..begin(
        position: const Offset(900, 800),
        size: const Size(1000, 1600),
        direction: 1,
      )
      ..update(const Offset(400, 800))
      ..release(horizontalVelocity: -1200);
    addTearDown(controller.dispose);
    PageSlideRelease? received;

    controller.attach((release) => received = release);
    await Future<void>.delayed(Duration.zero);

    expect(received, isNotNull);
    expect(received!.normalizedVelocity, -1200);
    expect(received!.alongPixels, greaterThan(pageSlideMinCommitTravel));
  });

  test('tap can force completion without drag velocity', () async {
    final controller = PageSlideController()
      ..begin(
        position: const Offset(900, 800),
        size: const Size(1000, 1600),
        direction: 1,
      );
    addTearDown(controller.dispose);
    PageSlideRelease? received;
    controller.attach((release) => received = release);

    controller.release(horizontalVelocity: 0, forceComplete: true);

    expect(received?.forceComplete, isTrue);
  });
}
