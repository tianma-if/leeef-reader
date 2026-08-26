import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/export/note_export_service.dart';

void main() {
  final createdAt = DateTime.utc(2026, 8, 26, 12);
  final books = [
    BookRecord(
      id: 'book-1',
      sha256: 'a' * 64,
      title: 'A, "Book"',
      author: 'Author',
      description: null,
      mediaType: 'application/epub+zip',
      filePath: null,
      coverPath: null,
      isAvailableLocally: false,
      isDeleted: false,
      createdAt: createdAt,
      updatedAt: createdAt,
    ),
  ];
  final excerpts = [
    ExcerptRecord(
      id: 'excerpt-1',
      bookId: 'book-1',
      locator: 'epubcfi(/6/2)',
      quote: 'Line one\nLine two',
      note: 'A useful idea',
      color: 'yellow',
      isDeleted: false,
      createdAt: createdAt,
      updatedAt: createdAt,
    ),
  ];
  const service = NoteExportService();

  test('exports grouped Markdown with quote and note', () {
    final output = service.export(
      excerpts: excerpts,
      books: books,
      format: NoteExportFormat.markdown,
    );

    expect(output, contains('## A, "Book"'));
    expect(output, contains('> Line one\n> Line two'));
    expect(output, contains('- 笔记：A useful idea'));
  });

  test('exports RFC-style escaped CSV cells', () {
    final output = service.export(
      excerpts: excerpts,
      books: books,
      format: NoteExportFormat.csv,
    );

    expect(output, startsWith('"书名","原文"'));
    expect(output, contains('"A, ""Book"""'));
    expect(output, contains('"Line one\nLine two"'));
    expect(output, endsWith('\r\n'));
  });

  test('chapter merged export produces continuous book sections', () {
    final output = service.export(
      excerpts: excerpts,
      books: books,
      format: NoteExportFormat.chapterMerged,
    );

    expect(output, startsWith('# Leeef 章节合并书摘'));
    expect(output, contains('## A, "Book"'));
    expect(output, contains('Line one\nLine two'));
    expect(output, contains('> 笔记：A useful idea'));
  });
}
