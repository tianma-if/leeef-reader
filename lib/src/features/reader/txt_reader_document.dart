import 'dart:convert';
import 'dart:typed_data';

class TxtPage {
  const TxtPage({required this.start, required this.end, required this.text});

  final int start;
  final int end;
  final String text;
}

class TxtChapter {
  const TxtChapter({required this.title, required this.offset});

  final String title;
  final int offset;
}

class TxtReaderDocument {
  const TxtReaderDocument({
    required this.text,
    required this.pages,
    required this.chapters,
  });

  factory TxtReaderDocument.decode(Uint8List bytes, {int pageLength = 1800}) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\ufeff')) text = text.substring(1);
    return TxtReaderDocument.fromText(text, pageLength: pageLength);
  }

  factory TxtReaderDocument.fromText(String text, {int pageLength = 1800}) {
    if (pageLength < 1) {
      throw ArgumentError.value(pageLength, 'pageLength', 'Must be positive.');
    }
    final pages = <TxtPage>[];
    if (text.isEmpty) {
      pages.add(const TxtPage(start: 0, end: 0, text: ''));
    } else {
      var start = 0;
      while (start < text.length) {
        var end = (start + pageLength).clamp(0, text.length);
        if (end < text.length) {
          final searchStart = start + (pageLength * 0.55).round();
          final newline = text.lastIndexOf('\n', end);
          if (newline >= searchStart) end = newline + 1;
          if (end < text.length && _splitsSurrogatePair(text, end)) end--;
        }
        pages.add(
          TxtPage(start: start, end: end, text: text.substring(start, end)),
        );
        start = end;
      }
    }

    final chapters = <TxtChapter>[];
    final heading = RegExp(
      r'^(?:第.{1,12}[章节卷回部篇]|chapter\s+\d+\b).{0,50}$',
      caseSensitive: false,
    );
    var offset = 0;
    for (final line in text.split('\n')) {
      final candidate = line.trim();
      if (candidate.isNotEmpty && heading.hasMatch(candidate)) {
        chapters.add(TxtChapter(title: candidate, offset: offset));
      }
      offset += line.length + 1;
    }
    return TxtReaderDocument(text: text, pages: pages, chapters: chapters);
  }

  final String text;
  final List<TxtPage> pages;
  final List<TxtChapter> chapters;

  int pageIndexForOffset(int offset) {
    final safe = offset.clamp(0, text.length);
    final index = pages.indexWhere(
      (page) => safe >= page.start && safe < page.end,
    );
    return index < 0 ? pages.length - 1 : index;
  }

  static bool _splitsSurrogatePair(String text, int offset) {
    if (offset <= 0 || offset >= text.length) return false;
    return _isHighSurrogate(text.codeUnitAt(offset - 1)) &&
        _isLowSurrogate(text.codeUnitAt(offset));
  }

  static bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;
  static bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;
}

int parseTxtLocator(String? locator) {
  if (locator == null || !locator.startsWith('txt:')) return 0;
  return int.tryParse(locator.substring(4)) ?? 0;
}

String txtLocator(int offset) => 'txt:$offset';
