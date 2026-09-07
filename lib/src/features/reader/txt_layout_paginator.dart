import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:leeef_reader/src/features/reader/txt_reader_document.dart';

class TxtDisplayText {
  const TxtDisplayText({required this.text, required this.offsets});

  final String text;
  final List<int> offsets;

  int originalOffset(int displayOffset) =>
      offsets[displayOffset.clamp(0, offsets.length - 1)];
}

typedef TxtDisplayTextBuilder = TxtDisplayText Function(String source);

/// Measures each page with the same Flutter layout and display transformation
/// as the reader. Searches bounded source slices, never the entire remaining
/// book, so long novels do not require quadratic text layout work.
List<TxtPage> paginateTxtForLayout({
  required String text,
  required double maxWidth,
  required double maxHeight,
  required TextStyle style,
  required TextDirection textDirection,
  required TxtDisplayTextBuilder buildDisplayText,
  TextScaler textScaler = TextScaler.noScaling,
  TextAlign textAlign = TextAlign.start,
}) {
  if (text.isEmpty) {
    return const [TxtPage(start: 0, end: 0, text: '')];
  }
  final pages = <TxtPage>[];
  final paginator = _TxtLayoutPaginator(
    text: text,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    style: style,
    textDirection: textDirection,
    buildDisplayText: buildDisplayText,
    textScaler: textScaler,
    textAlign: textAlign,
  );
  try {
    while (!paginator.isDone) {
      pages.add(paginator.nextPage());
    }
  } finally {
    paginator.dispose();
  }
  return pages;
}

/// Paginates without monopolizing Flutter's UI isolate.
///
/// Text measurement must run on the UI isolate, but yielding between small
/// batches lets pointer events and frames continue while a long novel is being
/// prepared. A cancelled run returns `null` at the next page boundary.
Future<List<TxtPage>?> paginateTxtForLayoutCooperatively({
  required String text,
  required double maxWidth,
  required double maxHeight,
  required TextStyle style,
  required TextDirection textDirection,
  required TxtDisplayTextBuilder buildDisplayText,
  TextScaler textScaler = TextScaler.noScaling,
  TextAlign textAlign = TextAlign.start,
  int pagesPerBatch = 8,
  bool Function()? isCancelled,
}) async {
  if (pagesPerBatch < 1) {
    throw ArgumentError.value(pagesPerBatch, 'pagesPerBatch');
  }
  if (text.isEmpty) {
    return const [TxtPage(start: 0, end: 0, text: '')];
  }
  final pages = <TxtPage>[];
  final paginator = _TxtLayoutPaginator(
    text: text,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    style: style,
    textDirection: textDirection,
    buildDisplayText: buildDisplayText,
    textScaler: textScaler,
    textAlign: textAlign,
  );
  try {
    while (!paginator.isDone) {
      for (var index = 0; index < pagesPerBatch && !paginator.isDone; index++) {
        if (isCancelled?.call() ?? false) return null;
        pages.add(paginator.nextPage());
      }
      if (!paginator.isDone) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return pages;
  } finally {
    paginator.dispose();
  }
}

class _TxtLayoutPaginator {
  _TxtLayoutPaginator({
    required this.text,
    required this.maxWidth,
    required this.maxHeight,
    required this.style,
    required TextDirection textDirection,
    required this.buildDisplayText,
    required TextScaler textScaler,
    required TextAlign textAlign,
  }) : _painter = TextPainter(
         textDirection: textDirection,
         textScaler: textScaler,
         textAlign: textAlign,
         strutStyle: StrutStyle.fromTextStyle(style),
       ) {
    if (!maxWidth.isFinite ||
        !maxHeight.isFinite ||
        maxWidth <= 0 ||
        maxHeight <= 0) {
      throw ArgumentError('TXT page dimensions must be finite and positive.');
    }
  }

  final String text;
  final double maxWidth;
  final double maxHeight;
  final TextStyle style;
  final TxtDisplayTextBuilder buildDisplayText;
  final TextPainter _painter;
  var _start = 0;
  var _estimatedCharacters = 1024;

  bool get isDone => _start >= text.length;

  TxtPage nextPage() {
    if (isDone) throw StateError('TXT pagination is already complete.');

    var low = 0;
    var high = _estimatedCharacters;
    var highEnd = _endAfter(high);
    while (_fits(highEnd)) {
      low = high;
      if (highEnd == text.length) break;
      high *= 2;
      highEnd = _endAfter(high);
    }
    while (low + 1 < high) {
      final middle = (low + high) ~/ 2;
      final middleEnd = _endAfter(middle);
      if (_fits(middleEnd)) {
        low = middle;
      } else {
        high = middle;
      }
    }

    // Even a viewport shorter than one line must make forward progress. The
    // range API keeps emoji and combining sequences on the same page.
    final fittedCharacters = math.max(1, low);
    final end = _endAfter(fittedCharacters);
    final page = TxtPage(
      start: _start,
      end: end,
      text: text.substring(_start, end),
    );
    _start = end;
    _estimatedCharacters = fittedCharacters;
    return page;
  }

  int _endAfter(int characterCount) {
    final range = CharacterRange.at(text, _start);
    range.expandNext(characterCount);
    return text.length - range.stringAfterLength;
  }

  bool _fits(int end) {
    final source = text.substring(_start, end);
    _painter.text = TextSpan(text: buildDisplayText(source).text, style: style);
    _painter.layout(maxWidth: maxWidth);
    return _painter.height <= maxHeight;
  }

  void dispose() => _painter.dispose();
}
