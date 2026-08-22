import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/features/reader/txt_reader_document.dart';

void main() {
  test(
    'decodes UTF-8 BOM, detects chapters, and paginates on line boundaries',
    () {
      final bytes = utf8.encode('\ufeff第一章 开始\n${'正文内容' * 20}\n第二章 继续\n结尾');

      final document = TxtReaderDocument.decode(bytes, pageLength: 40);

      expect(document.text, startsWith('第一章'));
      expect(document.chapters.map((chapter) => chapter.title), [
        '第一章 开始',
        '第二章 继续',
      ]);
      expect(document.pages, hasLength(greaterThan(1)));
      expect(document.pages.map((page) => page.text).join(), document.text);
      expect(document.pages.first.end, document.pages[1].start);
    },
  );

  test('stable offset locator restores the page and never splits emoji', () {
    final document = TxtReaderDocument.fromText(
      'abcd😀efghijkl',
      pageLength: 5,
    );
    final offset = document.text.indexOf('e');
    final page = document.pages[document.pageIndexForOffset(offset)];

    expect(page.text.runes.contains(0xFFFD), isFalse);
    expect(parseTxtLocator(txtLocator(offset)), offset);
    expect(offset, inInclusiveRange(page.start, page.end));
  });

  test('malformed bytes remain readable instead of failing the import', () {
    final document = TxtReaderDocument.decode(
      Uint8List.fromList(utf8.encode('开头') + [0xFF, 0xFE] + utf8.encode('结尾')),
    );

    expect(document.text, contains('开头'));
    expect(document.text, contains('结尾'));
  });
}
