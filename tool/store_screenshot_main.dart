import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:leeef_reader/main.dart' as production;
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/repositories/library_repository.dart';
import 'package:leeef_reader/src/domain/reading_location.dart';
import 'package:leeef_reader/src/import/book_import_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Screenshot-only entry point used to create reproducible store artwork.
///
/// Run with:
/// `flutter run -t tool/store_screenshot_main.dart -d <device>`
Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await _seedStoreDemo();
  await production.main(arguments);
}

Future<void> _seedStoreDemo() async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setBool('leeef.onboarding.completed', true);
  await preferences.setString('leeef.appearance.locale', 'zh');

  final database = AppDatabase();
  final repository = LibraryRepository(
    database: database,
    deviceId: 'store-screenshot-device',
  );
  try {
    final existing = await repository.listBooks();
    if (existing.isNotEmpty &&
        await Future.wait(
          existing.map(
            (book) async =>
                book.filePath != null && await File(book.filePath!).exists(),
          ),
        ).then((files) => files.every((exists) => exists))) {
      return;
    }

    final documents = await getApplicationDocumentsDirectory();
    final staging = Directory('${documents.path}/store-screenshot-source');
    final library = Directory('${documents.path}/leeef/books');
    await staging.create(recursive: true);
    final importer = BookImportService(
      repository: repository,
      libraryDirectory: library,
    );

    final fixtureBytes = await rootBundle.load('assets/fixtures/m0.epub');
    final fixture = File('${staging.path}/月光下的阅读.epub');
    await fixture.writeAsBytes(fixtureBytes.buffer.asUint8List(), flush: true);
    final featured = await importer.importFile(fixture);
    await repository.updateBookMetadata(
      bookId: featured.id,
      title: '月光下的阅读',
      author: 'Leeef 编辑部',
      description: '一本用于展示专注阅读、书摘与笔记体验的短篇读物。',
    );

    const companionBooks = <(String, String, String)>[
      ('把时间当作朋友', '阅读札记', '真正的成长来自持续行动与耐心积累。'),
      ('山川与四季', '林间', '清晨的光穿过叶隙，落在仍带露水的书页上。'),
      ('思考的边界', '知行', '问题的边界，常常决定了答案能够抵达的地方。'),
    ];
    for (final (title, author, body) in companionBooks) {
      final source = File('${staging.path}/$title.txt');
      await source.writeAsString(
        '$title\n\n$body\n\n阅读让匆忙的日常重新拥有层次，也让每一次停顿都成为新的出发。',
        flush: true,
      );
      final book = await importer.importFile(source);
      await repository.updateBookMetadata(
        bookId: book.id,
        title: title,
        author: author,
        description: body,
      );
    }

    if (await repository.getReadingProgress(featured.id) == null) {
      await repository.updateReadingProgress(
        bookId: featured.id,
        location: const ReadingLocation(
          locator: 'EPUB/chapter.xhtml',
          progress: 0.38,
          chapterTitle: '第一章',
          page: 12,
        ),
      );
    }
    if ((await repository.listExcerpts(bookId: featured.id)).isEmpty) {
      await repository.createExcerpt(
        bookId: featured.id,
        locator: 'EPUB/chapter.xhtml',
        quote: '阅读不是逃离生活，而是带着更清醒的目光重新回到生活。',
        note: '真正重要的不是读完多少，而是留下了什么。',
        color: 'green',
      );
      await repository.createExcerpt(
        bookId: featured.id,
        locator: 'EPUB/chapter.xhtml',
        quote: '每一次专注，都是在为自己保留一片安静的森林。',
        note: '适合在忙碌时提醒自己。',
        color: 'yellow',
      );
    }
    if ((await database.select(database.bookmarks).get()).isEmpty) {
      await repository.createBookmark(
        bookId: featured.id,
        locator: 'EPUB/chapter.xhtml',
        title: '第一章 · 阅读与生活',
        note: '下次从这里继续',
      );
    }

    final now = DateTime.now();
    if ((await database.select(database.readingSessions).get()).isEmpty) {
      for (var day = 0; day < 18; day += 2) {
        final endedAt = DateTime(
          now.year,
          now.month,
          now.day,
          21,
        ).subtract(Duration(days: day));
        final minutes = 18 + (day % 5) * 7;
        await repository.recordReadingSession(
          bookId: featured.id,
          startedAt: endedAt.subtract(Duration(minutes: minutes)),
          endedAt: endedAt,
        );
      }
    }
  } finally {
    await database.close();
  }
}
