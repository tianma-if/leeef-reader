import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/domain/reading_location.dart';

void main() {
  test('reading location JSON round-trips', () {
    const location = ReadingLocation(
      locator: 'epubcfi(/6/4!/4/2/1:0)',
      progress: 0.42,
      chapterTitle: '第二章',
      page: 18,
    );

    final decoded = ReadingLocation.fromJson(location.toJson());

    expect(decoded.locator, location.locator);
    expect(decoded.progress, location.progress);
    expect(decoded.chapterTitle, location.chapterTitle);
    expect(decoded.page, location.page);
  });

  test('invalid progress from remote operation is rejected', () {
    expect(
      () => ReadingLocation.fromJson({'locator': 'cfi', 'progress': 1.2}),
      throwsFormatException,
    );
  });
}
