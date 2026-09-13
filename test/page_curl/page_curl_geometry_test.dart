import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/page_curl/page_curl_geometry.dart';

void main() {
  test('mid-edge drag uses a near-vertical cylinder instead of a corner flap', () {
    final geometry = PageCurlGeometry.compute(
      size: const Size(400, 800),
      travel: 0.45,
      touchY: 0.52,
    );

    expect(geometry.grab.dy, closeTo(416, 1));
    expect(geometry.normal.dx.abs(), greaterThan(geometry.normal.dy.abs()));
    expect(geometry.radius, greaterThan(18));
  });

  test('bottom-edge grab still peels from the page corner', () {
    final geometry = PageCurlGeometry.compute(
      size: const Size(400, 600),
      travel: 0.5,
      touchY: 0.9,
    );

    expect(geometry.grab.dy, 600);
    expect(geometry.touch.dy, greaterThan(300));
  });

  test('top-edge grab peels from the upper corner', () {
    final geometry = PageCurlGeometry.compute(
      size: const Size(400, 600),
      travel: 0.4,
      touchY: 0.12,
    );

    expect(geometry.grab.dy, 0);
  });
}
