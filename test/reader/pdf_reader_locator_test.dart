import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/features/reader/pdf_reader_screen.dart';

void main() {
  test('PDF page locators round-trip and reject invalid locations', () {
    expect(parsePdfPageLocator(pdfPageLocator(42)), 42);
    expect(parsePdfPageLocator('pdf:7:10-7:20'), 7);
    expect(parsePdfPageLocator('pdf:0'), 1);
    expect(parsePdfPageLocator('epubcfi(/6/2)'), 1);
    expect(parsePdfPageLocator(null), 1);
  });
}
