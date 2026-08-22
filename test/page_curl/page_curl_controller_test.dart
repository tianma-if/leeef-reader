import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/page_curl/page_curl_controller.dart';

void main() {
  test('pressing the edge immediately lifts the page corner', () {
    final controller = PageCurlController()
      ..begin(
        position: const Offset(900, 800),
        size: const Size(1000, 1600),
        direction: 1,
      );
    addTearDown(controller.dispose);

    expect(controller.progress, greaterThan(0));
    expect(controller.progress, lessThan(0.03));
  });

  test('forward and backward drags map to the same curl progress', () {
    final forward = PageCurlController()
      ..begin(
        position: const Offset(900, 800),
        size: const Size(1000, 1600),
        direction: 1,
      )
      ..update(const Offset(470, 600));
    final backward = PageCurlController()
      ..begin(
        position: const Offset(100, 800),
        size: const Size(1000, 1600),
        direction: -1,
      )
      ..update(const Offset(530, 600));
    addTearDown(forward.dispose);
    addTearDown(backward.dispose);

    expect(forward.progress, closeTo(0.5, 0.001));
    expect(backward.progress, closeTo(0.5, 0.001));
    expect(forward.touchY, closeTo(0.375, 0.001));
  });

  test('release survives snapshot delay before surface attaches', () async {
    final controller = PageCurlController()
      ..begin(
        position: const Offset(900, 800),
        size: const Size(1000, 1600),
        direction: 1,
      )
      ..update(const Offset(650, 800))
      ..release(horizontalVelocity: -1200);
    addTearDown(controller.dispose);
    PageCurlRelease? received;

    controller.attach((release) => received = release);
    await Future<void>.delayed(Duration.zero);

    expect(received, isNotNull);
    expect(received!.normalizedVelocity, -1200);
  });

  test('tap can force completion without fake drag velocity', () async {
    final controller = PageCurlController()
      ..begin(
        position: const Offset(900, 800),
        size: const Size(1000, 1600),
        direction: 1,
      );
    addTearDown(controller.dispose);
    PageCurlRelease? received;
    controller.attach((release) => received = release);

    controller.release(horizontalVelocity: 0, forceComplete: true);

    expect(received?.forceComplete, isTrue);
  });
}
