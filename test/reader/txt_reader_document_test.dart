import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart' as charset;
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

    expect(document.text, isNotEmpty);
  });

  test('detects common GBK Chinese TXT files', () {
    final document = TxtReaderDocument.decode(
      Uint8List.fromList(charset.gbk.encode('第一章 GBK 文本\n正文可以阅读')),
    );

    expect(document.text, '第一章 GBK 文本\n正文可以阅读');
    expect(document.chapters.single.title, '第一章 GBK 文本');
  });

  test('detects common web-novel headings and strips site metadata', () {
    final document = TxtReaderDocument.fromText('''
书籍介绍
正文 第一节
第一节内容
第一种人只是正文，不是标题。
【第二章 新的开始】
第二章内容
第三节 重逢 更新时间:2026-08-23 12:00 本章字数:1234
楔子 往事
Chapter 5 Finale
''');

    expect(document.chapters.map((chapter) => chapter.title), [
      '第一节',
      '第二章 新的开始',
      '第三节 重逢',
      '楔子 往事',
      'Chapter 5 Finale',
    ]);
    for (final chapter in document.chapters) {
      expect(document.text.substring(chapter.offset), contains(chapter.title));
      expect(
        document.pages[document.pageIndexForOffset(chapter.offset)].start,
        chapter.offset,
      );
    }
  });

  test('detects alternate volume labels and common ending sections', () {
    final document = TxtReaderDocument.fromText('''
卷一 初见
正文
终章 再会
番外篇 婚礼
后记
''');

    expect(document.chapters.map((chapter) => chapter.title), [
      '卷一 初见',
      '终章 再会',
      '番外篇 婚礼',
      '后记',
    ]);
  });
}
