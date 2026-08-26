import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/features/reader/pdf_reader_screen.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  test('PDF page locators round-trip and reject invalid locations', () {
    expect(parsePdfPageLocator(pdfPageLocator(42)), 42);
    expect(parsePdfPageLocator('pdf:7:10-7:20'), 7);
    expect(parsePdfPageLocator('pdf:0'), 1);
    expect(parsePdfPageLocator('epubcfi(/6/2)'), 1);
    expect(parsePdfPageLocator(null), 1);
  });

  test('PDF outline resolves the deepest latest chapter for a page', () {
    final entries = [
      const PdfOutlineEntry(
        title: 'Chapter 1',
        dest: PdfDest(1, PdfDestCommand.fit, null),
        depth: 0,
      ),
      const PdfOutlineEntry(
        title: 'Section 1.2',
        dest: PdfDest(4, PdfDestCommand.fit, null),
        depth: 1,
      ),
      const PdfOutlineEntry(
        title: 'Chapter 2',
        dest: PdfDest(9, PdfDestCommand.fit, null),
        depth: 0,
      ),
    ];

    expect(pdfChapterTitleForPage(entries, 1), 'Chapter 1');
    expect(pdfChapterTitleForPage(entries, 7), 'Section 1.2');
    expect(pdfChapterTitleForPage(entries, 12), 'Chapter 2');
  });
}
