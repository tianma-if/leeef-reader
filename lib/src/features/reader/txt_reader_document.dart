import 'dart:convert';
import 'dart:isolate';
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
    bool includeCharacterPages = true,
    bool includeChapters = true,
  }) {
    return TxtReaderDocument.fromText(
      decodeTxtBytes(bytes),
      pageLength: pageLength,
      chapterPattern: chapterPattern,
      includeCharacterPages: includeCharacterPages,
      includeChapters: includeChapters,
    );
  }

  factory TxtReaderDocument.fromText(
    String text, {
    int pageLength = 1800,
    String chapterPattern = '',
    bool includeCharacterPages = true,
    bool includeChapters = true,
  }) {
    if (pageLength < 1) {
      throw ArgumentError.value(pageLength, 'pageLength', 'Must be positive.');
    }
    final chapters = includeChapters
        ? extractTxtChapters(text, chapterPattern: chapterPattern)
        : const <TxtChapter>[];

    final pages = <TxtPage>[];
    if (!includeCharacterPages) {
      pages.add(TxtPage(start: 0, end: text.length, text: ''));
    } else if (text.isEmpty) {
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

  int pageIndexForOffset(int offset) => txtPageIndexForOffset(pages, offset);

  static bool _splitsSurrogatePair(String text, int offset) {
    if (offset <= 0 || offset >= text.length) return false;
    return _isHighSurrogate(text.codeUnitAt(offset - 1)) &&
        _isLowSurrogate(text.codeUnitAt(offset));
  }

  static bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;
  static bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;

  static String? extractChapterTitle(String line) {
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

  TxtReaderDocument withChapters(List<TxtChapter> chapters) =>
      TxtReaderDocument(text: text, pages: pages, chapters: chapters);
}

String decodeTxtBytes(Uint8List bytes) {
  var text = _decodeTxtBytes(bytes);
  if (text.startsWith('\ufeff')) text = text.substring(1);
  return text;
}

/// Decodes only the leading [maxChars] so the first page can paint before a
/// multi-million-character novel is fully inflated in memory.
String decodeTxtPrefix(Uint8List bytes, int maxChars) {
  if (maxChars < 1) return '';
  if (charset.hasUtf16BeBom(bytes) ||
      charset.hasUtf16LeBom(bytes) ||
      charset.hasUtf32Bom(bytes)) {
    final text = decodeTxtBytes(bytes);
    return text.length <= maxChars ? text : text.substring(0, maxChars);
  }
  final sampleEnd = bytes.length < 4096 ? bytes.length : 4096;
  var utf8Text = false;
  try {
    utf8.decode(bytes.sublist(0, sampleEnd));
    utf8Text = true;
  } on FormatException {
    utf8Text = false;
  }
  late final String text;
  if (utf8Text) {
    var start = 0;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      start = 3;
    }
    final byteEnd = (start + maxChars * 4).clamp(0, bytes.length);
    text = utf8.decode(bytes.sublist(0, byteEnd), allowMalformed: true);
  } else {
    final byteEnd = (maxChars * 2 + 32).clamp(0, bytes.length);
    text = const charset.GbkCodec(
      allowMalformed: true,
    ).decode(bytes.sublist(0, byteEnd));
  }
  final stripped = text.startsWith('\ufeff') ? text.substring(1) : text;
  return stripped.length <= maxChars
      ? stripped
      : stripped.substring(0, maxChars);
}

List<TxtChapter> extractTxtChapters(String text, {String chapterPattern = ''}) {
  final chapters = <TxtChapter>[];
  RegExp? customPattern;
  if (chapterPattern.trim().isNotEmpty) {
    try {
      customPattern = RegExp(chapterPattern, caseSensitive: false);
    } on FormatException {
      customPattern = null;
    }
  }
  var offset = 0;
  while (offset < text.length) {
    final newline = text.indexOf('\n', offset);
    final end = newline < 0 ? text.length : newline;
    final length = end - offset;
    if (length > 0 && length <= 100) {
      final line = text.substring(offset, end);
      final normalized = line.trim().replaceAll(RegExp(r'\s+'), ' ');
      final title = customPattern?.hasMatch(normalized) == true
          ? normalized
          : TxtReaderDocument.extractChapterTitle(line);
      if (title != null) {
        chapters.add(TxtChapter(title: title, offset: offset));
      }
    }
    offset = newline < 0 ? text.length : newline + 1;
  }
  return chapters;
}

String _decodeTxtBytes(Uint8List bytes) {
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

Future<TxtReaderDocument> decodeTxtDocumentInBackground(
  Uint8List bytes, {
  int pageLength = 1800,
  String chapterPattern = '',
  bool includeCharacterPages = true,
  bool includeChapters = true,
}) => Isolate.run(
  () => TxtReaderDocument.decode(
    bytes,
    pageLength: pageLength,
    chapterPattern: chapterPattern,
    includeCharacterPages: includeCharacterPages,
    includeChapters: includeChapters,
  ),
);

Future<TxtReaderDocument> parseTxtDocumentInBackground(
  String text, {
  int pageLength = 1800,
  String chapterPattern = '',
  bool includeCharacterPages = true,
  bool includeChapters = true,
}) => Isolate.run(
  () => TxtReaderDocument.fromText(
    text,
    pageLength: pageLength,
    chapterPattern: chapterPattern,
    includeCharacterPages: includeCharacterPages,
    includeChapters: includeChapters,
  ),
);

int txtPageIndexForOffset(List<TxtPage> pages, int offset) {
  if (pages.isEmpty) return 0;
  var lo = 0;
  var hi = pages.length - 1;
  final lastEnd = pages.last.end;
  final safe = offset.clamp(0, lastEnd);
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final page = pages[mid];
    if (safe < page.start) {
      hi = mid - 1;
    } else if (safe >= page.end && mid < pages.length - 1) {
      lo = mid + 1;
    } else {
      return mid;
    }
  }
  return pages.length - 1;
}

int parseTxtLocator(String? locator) {
  if (locator == null || !locator.startsWith('txt:')) return 0;
  return int.tryParse(locator.substring(4)) ?? 0;
}

String txtLocator(int offset) => 'txt:$offset';
