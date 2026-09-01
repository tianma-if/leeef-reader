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

/// Splits TXT content into pages that remain inside the visible text area.
///
/// Character-count pagination cannot guarantee that a page fits after the
/// window size, font, line height, or margins change. This paginator measures
/// the active Flutter font, applies conservative glyph widths, and maps every
/// displayed seam back to the original source offset.
List<TxtPage> paginateTxtForLayout({
  required String text,
  required double maxWidth,
  required double maxHeight,
  required TextStyle style,
  required TextDirection textDirection,
  required TxtDisplayTextBuilder buildDisplayText,
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

  final display = buildDisplayText(text);
  final metrics = _TxtGlyphMetrics.measure(style, textDirection);
  final lineWidth = maxWidth * 0.96;
  final linesPerPage = math.max(1, (maxHeight / metrics.lineHeight).floor());
  final pages = <TxtPage>[];
  var pageStart = 0;
  var usedLines = 1;
  var usedWidth = 0.0;
  var displayOffset = 0;

  void addPage(int sourceEnd) {
    var end = sourceEnd.clamp(pageStart + 1, text.length);
    if (_splitsSurrogatePair(text, end)) end--;
    if (end <= pageStart) end = pageStart + _firstRuneLength(text, pageStart);
    pages.add(
      TxtPage(start: pageStart, end: end, text: text.substring(pageStart, end)),
    );
    pageStart = end;
    usedLines = 1;
    usedWidth = 0;
  }

  while (displayOffset < display.text.length) {
    final firstCodeUnit = display.text.codeUnitAt(displayOffset);
    final hasSurrogatePair =
        _isHighSurrogate(firstCodeUnit) &&
        displayOffset + 1 < display.text.length &&
        _isLowSurrogate(display.text.codeUnitAt(displayOffset + 1));
    final runeLength = hasSurrogatePair ? 2 : 1;
    final codePoint = hasSurrogatePair
        ? 0x10000 +
              ((firstCodeUnit - 0xD800) << 10) +
              (display.text.codeUnitAt(displayOffset + 1) - 0xDC00)
        : firstCodeUnit;
    if (codePoint == 0x0A) {
      if (usedLines >= linesPerPage) {
        final sourceEnd = display.originalOffset(displayOffset + runeLength);
        if (sourceEnd > pageStart) {
          addPage(sourceEnd);
        } else {
          usedLines = 1;
          usedWidth = 0;
        }
      } else {
        usedLines++;
        usedWidth = 0;
      }
      displayOffset += runeLength;
      continue;
    }

    final glyphWidth = metrics.widthFor(codePoint);
    if (usedWidth > 0 && usedWidth + glyphWidth > lineWidth) {
      if (usedLines >= linesPerPage) {
        final sourceEnd = display.originalOffset(displayOffset);
        if (sourceEnd > pageStart) addPage(sourceEnd);
      } else {
        usedLines++;
        usedWidth = 0;
      }
    }
    usedWidth += glyphWidth;
    displayOffset += runeLength;
  }

  if (pageStart < text.length) {
    pages.add(
      TxtPage(
        start: pageStart,
        end: text.length,
        text: text.substring(pageStart),
      ),
    );
  }
  return pages;
}

class _TxtGlyphMetrics {
  const _TxtGlyphMetrics({
    required this.lineHeight,
    required this.fullWidth,
    required this.regularWidth,
    required this.wideWidth,
    required this.narrowWidth,
    required this.spaceWidth,
  });

  factory _TxtGlyphMetrics.measure(
    TextStyle style,
    TextDirection textDirection,
  ) {
    ({double width, double height}) measure(String value) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: textDirection,
        maxLines: 1,
      )..layout();
      final result = (width: painter.width, height: painter.height);
      painter.dispose();
      return result;
    }

    final full = measure('国');
    final emoji = measure('😀');
    final regular = measure('n');
    final wide = measure('M');
    final narrow = measure('i');
    final spaces = measure('a a');
    final a = measure('aa');
    return _TxtGlyphMetrics(
      // TextPainter rounds baselines and paragraph boundaries slightly
      // differently when each page is laid out as its own widget. Reserving
      // one-tenth of a line keeps the reconstructed page inside the viewport.
      lineHeight: math.max(full.height, emoji.height) * 1.12,
      fullWidth: math.max(full.width, emoji.width) * 1.02,
      regularWidth: regular.width * 1.04,
      wideWidth: wide.width * 1.04,
      narrowWidth: narrow.width * 1.04,
      spaceWidth: math.max(1, spaces.width - a.width) * 1.04,
    );
  }

  final double lineHeight;
  final double fullWidth;
  final double regularWidth;
  final double wideWidth;
  final double narrowWidth;
  final double spaceWidth;

  double widthFor(int codePoint) {
    if (codePoint == 0x20 || codePoint == 0x09 || codePoint == 0xA0) {
      return spaceWidth;
    }
    if (codePoint > 0x7F) return fullWidth;
    final character = String.fromCharCode(codePoint);
    if ('ilI.,\'`!|:;'.contains(character)) return narrowWidth;
    if ('MW@#%&QO'.contains(character)) return wideWidth;
    return regularWidth;
  }
}

int _firstRuneLength(String text, int offset) {
  if (offset + 1 < text.length &&
      _isHighSurrogate(text.codeUnitAt(offset)) &&
      _isLowSurrogate(text.codeUnitAt(offset + 1))) {
    return 2;
  }
  return 1;
}

bool _splitsSurrogatePair(String text, int offset) =>
    offset > 0 &&
    offset < text.length &&
    _isHighSurrogate(text.codeUnitAt(offset - 1)) &&
    _isLowSurrogate(text.codeUnitAt(offset));

bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;
bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;
