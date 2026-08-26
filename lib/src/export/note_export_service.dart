import 'dart:convert';
import 'dart:typed_data';

import 'package:leeef_reader/src/data/database/app_database.dart';

enum NoteExportFormat { markdown, text, csv, chapterMerged }

class NoteExportService {
  const NoteExportService();

  String export({
    required List<ExcerptRecord> excerpts,
    required List<BookRecord> books,
    required NoteExportFormat format,
  }) {
    final titles = {for (final book in books) book.id: book.title};
    final sorted = [...excerpts]
      ..sort((left, right) {
        final book = (titles[left.bookId] ?? '').compareTo(
          titles[right.bookId] ?? '',
        );
        return book != 0 ? book : left.createdAt.compareTo(right.createdAt);
      });
    return switch (format) {
      NoteExportFormat.markdown => _markdown(sorted, titles),
      NoteExportFormat.text => _text(sorted, titles),
      NoteExportFormat.csv => _csv(sorted, titles),
      NoteExportFormat.chapterMerged => _chapterMerged(sorted, titles),
    };
  }

  static String extension(NoteExportFormat format) => switch (format) {
    NoteExportFormat.markdown => 'md',
    NoteExportFormat.text => 'txt',
    NoteExportFormat.csv => 'csv',
    NoteExportFormat.chapterMerged => 'md',
  };

  static String _chapterMerged(
    List<ExcerptRecord> excerpts,
    Map<String, String> titles,
  ) {
    final output = StringBuffer('# Leeef 章节合并书摘\n');
    String? currentBook;
    for (final excerpt in excerpts) {
      if (excerpt.bookId != currentBook) {
        currentBook = excerpt.bookId;
        output
          ..writeln()
          ..writeln('## ${_escapeMarkdown(titles[currentBook] ?? '未知书籍')}');
      }
      output
        ..writeln()
        ..writeln(excerpt.quote.trim());
      final note = excerpt.note?.trim();
      if (note != null && note.isNotEmpty) {
        output.writeln('\n> 笔记：$note');
      }
    }
    return '${output.toString().trimRight()}\n';
  }

  static String _markdown(
    List<ExcerptRecord> excerpts,
    Map<String, String> titles,
  ) {
    final output = StringBuffer('# Leeef 书摘与笔记\n');
    String? currentBook;
    for (final excerpt in excerpts) {
      if (excerpt.bookId != currentBook) {
        currentBook = excerpt.bookId;
        output
          ..writeln()
          ..writeln('## ${_escapeMarkdown(titles[currentBook] ?? '未知书籍')}');
      }
      output
        ..writeln()
        ..writeln('> ${excerpt.quote.replaceAll('\n', '\n> ')}')
        ..writeln()
        ..writeln('- 位置：`${excerpt.locator.replaceAll('`', r'\`')}`')
        ..writeln('- 时间：${excerpt.createdAt.toLocal().toIso8601String()}');
      final note = excerpt.note?.trim();
      if (note != null && note.isNotEmpty) output.writeln('- 笔记：$note');
    }
    return '${output.toString().trimRight()}\n';
  }

  static String _text(
    List<ExcerptRecord> excerpts,
    Map<String, String> titles,
  ) {
    final output = StringBuffer('Leeef 书摘与笔记\n');
    String? currentBook;
    for (final excerpt in excerpts) {
      if (excerpt.bookId != currentBook) {
        currentBook = excerpt.bookId;
        output
          ..writeln()
          ..writeln('《${titles[currentBook] ?? '未知书籍'}》');
      }
      output
        ..writeln()
        ..writeln(excerpt.quote)
        ..writeln('位置：${excerpt.locator}')
        ..writeln('时间：${excerpt.createdAt.toLocal().toIso8601String()}');
      final note = excerpt.note?.trim();
      if (note != null && note.isNotEmpty) output.writeln('笔记：$note');
    }
    return '${output.toString().trimRight()}\n';
  }

  static String _csv(List<ExcerptRecord> excerpts, Map<String, String> titles) {
    final rows = <List<String>>[
      const ['书名', '原文', '笔记', '颜色', '位置', '创建时间'],
      for (final excerpt in excerpts)
        [
          titles[excerpt.bookId] ?? '未知书籍',
          excerpt.quote,
          excerpt.note ?? '',
          excerpt.color,
          excerpt.locator,
          excerpt.createdAt.toLocal().toIso8601String(),
        ],
    ];
    return '${rows.map((row) => row.map(_csvCell).join(',')).join('\r\n')}\r\n';
  }

  static String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';

  static String _escapeMarkdown(String value) =>
      value.replaceAll(RegExp(r'([\\`*_{}\[\]()#+.!|>-])'), r'\$1');

  Uint8List encode(String content) => Uint8List.fromList(utf8.encode(content));
}
