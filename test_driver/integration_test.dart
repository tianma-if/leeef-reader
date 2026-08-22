import 'package:integration_test/integration_test_driver.dart';
import 'package:flutter_driver/flutter_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    await writeResponseData(data);
    final timelineJson = data?['page_curl_timeline'];
    if (timelineJson is! Map) {
      throw StateError('Page Curl timeline was not returned.');
    }
    final summary = TimelineSummary.summarize(
      Timeline.fromJson(Map<String, dynamic>.from(timelineJson)),
    );
    final buildP90 = summary.computePercentileFrameBuildTimeMillis(90);
    final rasterP90 = summary.computePercentileFrameRasterizerTimeMillis(90);
    final within120Hz = buildP90 < 8.33 && rasterP90 < 8.33;
    // ignore: avoid_print
    print(
      'PAGE_CURL_PERF build_p90=${buildP90.toStringAsFixed(3)}ms '
      'raster_p90=${rasterP90.toStringAsFixed(3)}ms '
      'within_120hz=$within120Hz',
    );
    if (buildP90 >= 16.67 || rasterP90 >= 16.67) {
      throw StateError('Page Curl exceeded the 60fps frame budget.');
    }
  },
);
