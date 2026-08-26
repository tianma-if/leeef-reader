import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/page_curl/page_curl_performance.dart';

void main() {
  test('calculates P90 and slow frame ratio for the display refresh rate', () {
    final report = PageCurlPerformanceMonitor.calculate(const [
      Duration(milliseconds: 5),
      Duration(milliseconds: 7),
      Duration(milliseconds: 8),
      Duration(milliseconds: 9),
      Duration(milliseconds: 10),
      Duration(milliseconds: 11),
      Duration(milliseconds: 12),
      Duration(milliseconds: 13),
      Duration(milliseconds: 18),
      Duration(milliseconds: 24),
    ], refreshRate: 60);

    expect(report.frameCount, 10);
    expect(report.slowFrames, 2);
    expect(report.slowFrameRatio, .2);
    expect(report.p90FrameTime, const Duration(milliseconds: 18));
    expect(report.estimatedFps, closeTo(55.56, .1));
  });

  test('uses the tighter high-refresh-rate frame budget', () {
    final report = PageCurlPerformanceMonitor.calculate(const [
      Duration(milliseconds: 7),
      Duration(milliseconds: 9),
    ], refreshRate: 120);
    expect(report.slowFrames, 1);
    expect(report.targetRefreshRate, 120);
  });
}
