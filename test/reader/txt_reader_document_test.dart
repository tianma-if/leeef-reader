import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart' as charset;
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/features/reader/txt_reader_document.dart';

void main() {
  test('large TXT decoding can run outside the UI isolate', () async {
    final source = '第一章 开始\n${'正文内容。' * 20000}';

    final document = await decodeTxtDocumentInBackground(
      Uint8List.fromList(utf8.encode(source)),
    );

    expect(document.text, source);
    expect(document.chapters.single.title, '第一章 开始');
    expect(document.pages.map((page) => page.text).join(), source);
  });

  test(
    'chapter-rule changes can rebuild a TXT outside the UI isolate',
    () async {
      const source = 'Part 1\nOpening\nPart 2\nEnding';

      final document = await parseTxtDocumentInBackground(
        source,
        chapterPattern: r'^Part \d+$',
      );

      expect(document.chapters.map((chapter) => chapter.title), [
        'Part 1',
        'Part 2',
      ]);
    },
  );

  test('custom chapter regex augments built-in heading detection', () {
    final document = TxtReaderDocument.fromText(
      'Part 1\nOpening\nPart 2\nEnding',
      chapterPattern: r'^Part \d+$',
    );

    expect(document.chapters.map((chapter) => chapter.title), [
      'Part 1',
      'Part 2',
    ]);
  });

  test('invalid custom chapter regex safely falls back to built-ins', () {
    final document = TxtReaderDocument.fromText(
      '第1章 开始\n正文',
      chapterPattern: '[',
    );

    expect(document.chapters.single.title, '第1章 开始');
  });

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

  test('utf-8 prefix decode matches the leading full-text characters', () {
    final source = '第一章 开始\n${'正文内容。' * 200}';
    final bytes = Uint8List.fromList(utf8.encode(source));
    expect(decodeTxtPrefix(bytes, 7), source.substring(0, 7));
    expect(decodeTxtPrefix(bytes, source.length), source);
  });

  test('gbk prefix decode keeps readable Chinese', () {
    const source = '第一章 开始\n赵玉台手持白马尾拂尘走下钟楼。';
    final bytes = Uint8List.fromList(const charset.GbkCodec().encode(source));
    expect(decodeTxtPrefix(bytes, 6), '第一章 开始');
    expect(decodeTxtPrefix(bytes, source.length), source);
  });

  test('text can be shown before chapters are extracted', () {
    final document = TxtReaderDocument.fromText(
      '第一章 开始\n正文内容。',
      includeCharacterPages: false,
      includeChapters: false,
    );
    expect(document.chapters, isEmpty);
    expect(document.text, contains('正文内容'));
    final withChapters = document.withChapters(
      extractTxtChapters(document.text),
    );
    expect(withChapters.chapters.single.title, '第一章 开始');
  });

  test('skipping character pages still keeps chapter offsets', () {
    final document = TxtReaderDocument.fromText(
      '第一章 开始\n${'正文内容。' * 400}\n第二章 继续\n结尾',
      includeCharacterPages: false,
    );
    expect(document.pages, hasLength(1));
    expect(document.pages.single.text, isEmpty);
    expect(document.chapters.map((chapter) => chapter.title), [
      '第一章 开始',
      '第二章 继续',
    ]);
  });

  test('txtReadingProgress is whole-book offset, not page count', () {
    expect(txtReadingProgress(offset: 0, length: 1000), 0);
    expect(txtReadingProgress(offset: 250, length: 1000), 0.25);
    expect(txtReadingProgress(offset: 1000, length: 1000), 1);
    expect(txtReadingProgress(offset: 50, length: 0), 0);
  });

  test('txtPageIndexForOffset binary-searches ordered pages', () {
    const pages = [
      TxtPage(start: 0, end: 10, text: '0123456789'),
      TxtPage(start: 10, end: 20, text: 'abcdefghij'),
      TxtPage(start: 20, end: 25, text: 'klmno'),
    ];
    expect(txtPageIndexForOffset(pages, 0), 0);
    expect(txtPageIndexForOffset(pages, 9), 0);
    expect(txtPageIndexForOffset(pages, 10), 1);
    expect(txtPageIndexForOffset(pages, 24), 2);
    expect(txtPageIndexForOffset(pages, 25), 2);
  });

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
