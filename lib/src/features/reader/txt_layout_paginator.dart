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
  if (!maxWidth.isFinite ||
      !maxHeight.isFinite ||
      maxWidth <= 0 ||
      maxHeight <= 0) {
    throw ArgumentError('TXT page dimensions must be finite and positive.');
  }

  // Search in graphemes, not UTF-16 units: neither emoji nor combining marks
  // may be split when a page is rebuilt as a separate SelectableText.
  final boundaries = <int>[0];
  for (final character in text.characters) {
    boundaries.add(boundaries.last + character.length);
  }
  final pages = <TxtPage>[];
  final painter = TextPainter(
    textDirection: textDirection,
    textScaler: textScaler,
    textAlign: textAlign,
    strutStyle: StrutStyle.fromTextStyle(style),
  );
  var start = 0;
  var estimatedLength = 1024;
  try {
    while (start < boundaries.length - 1) {
      bool fits(int end) {
        final source = text.substring(boundaries[start], boundaries[end]);
        painter.text = TextSpan(
          text: buildDisplayText(source).text,
          style: style,
        );
        painter.layout(maxWidth: maxWidth);
        return painter.height <= maxHeight;
      }

      var low = start;
      var high = math.min(start + estimatedLength, boundaries.length - 1);
      while (fits(high)) {
        low = high;
        if (high == boundaries.length - 1) break;
        high = math.min(start + (high - start) * 2, boundaries.length - 1);
      }
      while (low + 1 < high) {
        final middle = (low + high) ~/ 2;
        if (fits(middle)) {
          low = middle;
        } else {
          high = middle;
        }
      }
      // Even a viewport shorter than one line must make forward progress.
      final end = math.max(start + 1, low);
      pages.add(
        TxtPage(
          start: boundaries[start],
          end: boundaries[end],
          text: text.substring(boundaries[start], boundaries[end]),
        ),
      );
      estimatedLength = end - start;
      start = end;
    }
  } finally {
    painter.dispose();
  }
  return pages;
}
