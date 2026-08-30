import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/page_curl/page_curl_gesture.dart';

void main() {
  test('release travel starts without a jump and clears the viewport', () {
    expect(
      pageCurlSettlingTravel(
        progress: 0.43,
        startProgress: 0.43,
        complete: true,
      ),
      closeTo(0.43, 0.001),
    );
    expect(
      pageCurlSettlingTravel(progress: 1, startProgress: 0.43, complete: true),
      2,
    );
    expect(
      pageCurlSettlingTravel(
        progress: 0.44,
        startProgress: 0.43,
        complete: true,
      ),
      closeTo(0.44, 0.0001),
    );
    expect(
      pageCurlSettlingTravel(
        progress: 0.2,
        startProgress: 0.43,
        complete: false,
      ),
      0.2,
    );
  });

  test('left drag maps to normalized curl progress', () {
    final gesture = PageCurlGesture();

    expect(gesture.update(horizontalDelta: -25, width: 100), 0.25);
    expect(gesture.update(horizontalDelta: -50, width: 100), 0.75);
    expect(gesture.update(horizontalDelta: -100, width: 100), 1);
  });

  test('dragging back clamps progress and supports cancellation', () {
    final gesture = PageCurlGesture()..setProgress(0.4);

    expect(gesture.update(horizontalDelta: 20, width: 100), 0.2);
    expect(gesture.shouldComplete(0), isFalse);
    expect(gesture.update(horizontalDelta: 100, width: 100), 0);
  });

  test('distance or fling velocity completes the turn', () {
    final distanceGesture = PageCurlGesture()..setProgress(0.5);
    final flingGesture = PageCurlGesture()..setProgress(0.1);

    expect(distanceGesture.shouldComplete(0), isTrue);
    expect(flingGesture.shouldComplete(-900), isTrue);
    expect(flingGesture.shouldComplete(-300), isFalse);
  });
}
