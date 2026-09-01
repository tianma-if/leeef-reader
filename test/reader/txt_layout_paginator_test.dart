import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/features/reader/txt_layout_paginator.dart';

void main() {
  test('rendered TXT pages fit and preserve every source character', () {
    final source = List.generate(
      5000,
      (index) => String.fromCharCode(0x4E00 + index % 2000),
    ).join();
    const style = TextStyle(fontSize: 18, height: 1.65);
    final pages = paginateTxtForLayout(
      text: source,
      maxWidth: 640,
      maxHeight: 420,
      style: style,
      textDirection: TextDirection.ltr,
      buildDisplayText: _identityDisplay,
    );

    expect(pages.length, greaterThan(1));
    expect(pages.map((page) => page.text).join(), source);
    for (var index = 0; index < pages.length - 1; index++) {
      expect(pages[index].end, pages[index + 1].start);
      final painter = TextPainter(
        text: TextSpan(text: pages[index].text, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 640);
      expect(painter.height, lessThanOrEqualTo(420.01));
      painter.dispose();
    }
  });

  test('display-only indentation maps page seams back to source offsets', () {
    final source = List.generate(120, (index) => '段落$index 的正文内容。').join('\n');
    TxtDisplayText indented(String value) {
      final output = StringBuffer();
      final offsets = <int>[0];
      var sourceOffset = 0;
      for (final line in value.split('\n')) {
        output.write('　　');
        offsets.addAll([sourceOffset, sourceOffset]);
        for (final codeUnit in line.codeUnits) {
          output.writeCharCode(codeUnit);
          sourceOffset++;
          offsets.add(sourceOffset);
        }
        if (sourceOffset < value.length) {
          output.write('\n');
          sourceOffset++;
          offsets.add(sourceOffset);
        }
      }
      return TxtDisplayText(text: output.toString(), offsets: offsets);
    }

    final pages = paginateTxtForLayout(
      text: source,
      maxWidth: 360,
      maxHeight: 240,
      style: const TextStyle(fontSize: 18, height: 1.5),
      textDirection: TextDirection.ltr,
      buildDisplayText: indented,
    );

    expect(pages.map((page) => page.text).join(), source);
    for (var index = 0; index < pages.length - 1; index++) {
      expect(pages[index].end, pages[index + 1].start);
    }
  });

  test('Latin words and emoji also remain inside every page', () {
    final source = List.generate(
      400,
      (index) =>
          'Paragraph $index: Wide WWW, narrow iii, punctuation, and 😀 emoji.',
    ).join('\n');
    const style = TextStyle(fontSize: 17, height: 1.6);
    final pages = paginateTxtForLayout(
      text: source,
      maxWidth: 520,
      maxHeight: 360,
      style: style,
      textDirection: TextDirection.ltr,
      buildDisplayText: _identityDisplay,
    );

    expect(pages.map((page) => page.text).join(), source);
    for (final page in pages) {
      final painter = TextPainter(
        text: TextSpan(text: page.text, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 520);
      expect(painter.height, lessThanOrEqualTo(360.01));
      painter.dispose();
    }
  });
}

TxtDisplayText _identityDisplay(String source) => TxtDisplayText(
  text: source,
  offsets: List<int>.generate(source.length + 1, (index) => index),
);
