import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart' as charset;

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

  factory TxtReaderDocument.decode(
    Uint8List bytes, {
    int pageLength = 1800,
    String chapterPattern = '',
  }) {
    var text = _decodeText(bytes);
    if (text.startsWith('\ufeff')) text = text.substring(1);
    return TxtReaderDocument.fromText(
      text,
      pageLength: pageLength,
      chapterPattern: chapterPattern,
    );
  }

  factory TxtReaderDocument.fromText(
    String text, {
    int pageLength = 1800,
    String chapterPattern = '',
  }) {
    if (pageLength < 1) {
      throw ArgumentError.value(pageLength, 'pageLength', 'Must be positive.');
    }
    final chapters = <TxtChapter>[];
    RegExp? customPattern;
    if (chapterPattern.trim().isNotEmpty) {
      try {
        customPattern = RegExp(chapterPattern, caseSensitive: false);
      } on FormatException {
        customPattern = null;
      }
    }
    var lineOffset = 0;
    for (final line in text.split('\n')) {
      final normalized = line.trim().replaceAll(RegExp(r'\s+'), ' ');
      final title = customPattern?.hasMatch(normalized) == true
          ? normalized
          : _extractChapterTitle(line);
      if (title != null) {
        chapters.add(TxtChapter(title: title, offset: lineOffset));
      }
      lineOffset += line.length + 1;
    }

    final pages = <TxtPage>[];
    if (text.isEmpty) {
      pages.add(const TxtPage(start: 0, end: 0, text: ''));
    } else {
      var start = 0;
      var nextChapterIndex = 0;
      while (start < text.length) {
        var end = (start + pageLength).clamp(0, text.length);
        while (nextChapterIndex < chapters.length &&
            chapters[nextChapterIndex].offset <= start) {
          nextChapterIndex++;
        }
        final nextChapterOffset = nextChapterIndex < chapters.length
            ? chapters[nextChapterIndex].offset
            : text.length;
        if (nextChapterOffset > start && nextChapterOffset < end) {
          end = nextChapterOffset;
        }
        if (end < text.length) {
          final searchStart = start + (pageLength * 0.55).round();
          final newline = text.lastIndexOf('\n', end);
          if (end != nextChapterOffset && newline >= searchStart) {
            end = newline + 1;
          }
          if (end < text.length && _splitsSurrogatePair(text, end)) end--;
        }
        pages.add(
          TxtPage(start: start, end: end, text: text.substring(start, end)),
        );
        start = end;
      }
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

  static String? _extractChapterTitle(String line) {
    var candidate = line.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (candidate.isEmpty || candidate.length > 100) return null;

    candidate = candidate
        .replaceFirst(RegExp(r'\s*(?:更新时间|更新日期|发布时间)\s*[:：].*$'), '')
        .replaceFirst(RegExp(r'\s*本章字数\s*[:：].*$'), '');
    if (candidate.length >= 2) {
      const wrappers = <String, String>{'【': '】', '[': ']', '《': '》'};
      final closing = wrappers[candidate[0]];
      if (closing != null && candidate.endsWith(closing)) {
        candidate = candidate.substring(1, candidate.length - 1).trim();
      }
    }
    candidate = candidate.replaceFirst(RegExp(r'^正文\s+'), '');

    final numberedHeading = RegExp(
      r'^(?:(?:第\s*[〇零一二三四五六七八九十百千万两\d０-９]{1,12}\s*[章节卷回部篇集幕]|'
      r'[卷章节]\s*[〇零一二三四五六七八九十百千万两\d０-９]{1,12})'
      r'(?:$|[\s:：、.．—-].{0,60}$)|chapter\s+\d+\b(?:$|\s+.{1,60}$))',
      caseSensitive: false,
    );
    final namedHeading = RegExp(
      r'^(?:序章|序言|楔子|引子|前言|后记|尾声|终章|终卷|番外(?:篇|章)?)(?:\s*[-—:：、.]?\s*.{0,50})?$',
    );
    return numberedHeading.hasMatch(candidate) ||
            namedHeading.hasMatch(candidate)
        ? candidate
        : null;
  }

  static String _decodeText(Uint8List bytes) {
    if (charset.hasUtf16BeBom(bytes) || charset.hasUtf16LeBom(bytes)) {
      return charset.utf16.decode(bytes);
    }
    if (charset.hasUtf32Bom(bytes)) return charset.utf32.decode(bytes);
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3));
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return const charset.GbkCodec(allowMalformed: true).decode(bytes);
    }
  }
}

int parseTxtLocator(String? locator) {
  if (locator == null || !locator.startsWith('txt:')) return 0;
  return int.tryParse(locator.substring(4)) ?? 0;
}

String txtLocator(int offset) => 'txt:$offset';
