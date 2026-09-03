import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/features/reader/txt_layout_paginator.dart';

void main() {
  test('long novels are measured in bounded page-sized slices', () {
    final source = '长篇小说正文，用于检查分页性能。' * 62500;
    var largestSlice = 0;
    final timer = Stopwatch()..start();
    final pages = paginateTxtForLayout(
      text: source,
      maxWidth: 1100,
      maxHeight: 650,
      style: const TextStyle(fontSize: 18, height: 1.65),
      textDirection: TextDirection.ltr,
      buildDisplayText: (s) {
        if (s.length > largestSlice) largestSlice = s.length;
        return _identityDisplay(s);
      },
    );
    timer.stop();
    // Guard against accidentally laying out the remaining book on each page.
    expect(largestSlice, lessThan(8192));
    expect(pages.map((p) => p.text).join(), source);
    // Informational timing only: CI hardware and fonts vary.
    debugPrint(
      'TXT layout: ${source.length} code units, ${pages.length} pages, ${timer.elapsedMilliseconds} ms',
    );
  });

  for (final sample in [
    '这是连续的中文正文，包含标点。' * 500,
    'Wide WWW and narrow iii, words and punctuation. ' * 300,
    '👩🏽‍💻 café e\u0301 家庭👨‍👩‍👧‍👦，混合文字。' * 300,
    List.generate(120, (i) => '段落$i：${'长段落测试内容。' * 17}').join('\n\n'),
  ]) {
    test(
      'measured pages fill the viewport without losing graphemes (${sample.substring(0, 8)})',
      () {
        const style = TextStyle(fontSize: 18, height: 1.65, letterSpacing: 0.7);
        const scaler = TextScaler.linear(1.3);
        final pages = paginateTxtForLayout(
          text: sample,
          maxWidth: 713,
          maxHeight: 503,
          style: style,
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          buildDisplayText: _paragraphDisplay,
        );
        final painter = TextPainter(
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          strutStyle: StrutStyle.fromTextStyle(style),
        );
        addTearDown(painter.dispose);
        expect(pages.map((p) => p.text).join(), sample);
        expect(
          pages.expand((p) => p.text.characters).toList(),
          sample.characters.toList(),
        );
        for (var i = 0; i < pages.length; i++) {
          final page = pages[i];
          painter.text = TextSpan(
            text: _paragraphDisplay(page.text).text,
            style: style,
          );
          painter.layout(maxWidth: 713);
          expect(painter.height, lessThanOrEqualTo(503));
          if (i == pages.length - 1) continue;
          expect(page.end, pages[i + 1].start);
          // A page may not stop early when another whole character still fits.
          painter.text = TextSpan(
            text: _paragraphDisplay(
              page.text + pages[i + 1].text.characters.first,
            ).text,
            style: style,
          );
          painter.layout(maxWidth: 713);
          expect(painter.height, greaterThan(503));
        }
      },
    );
  }

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

TxtDisplayText _paragraphDisplay(String source) {
  final result = StringBuffer();
  final offsets = <int>[0];
  var offset = 0;
  for (final line in source.split('\n')) {
    if (line.trim().isNotEmpty) {
      result.write('　　');
      offsets.addAll([offset, offset]);
    }
    for (final unit in line.codeUnits) {
      result.writeCharCode(unit);
      offsets.add(++offset);
    }
    if (offset < source.length) {
      result.write('\n');
      offsets.add(++offset);
      if (line.trim().isNotEmpty) {
        result.write('\n');
        offsets.add(offset);
      }
    }
  }
  return TxtDisplayText(text: result.toString(), offsets: offsets);
}
