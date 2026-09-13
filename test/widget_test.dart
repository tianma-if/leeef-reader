import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leeef_reader/src/app.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/features/library/bookshelf_tiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('library empty state is visible', (tester) async {
    SharedPreferences.setMockInitialValues({
      'leeef.appearance.locale': 'zh',
      'leeef.onboarding.completed': true,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryBooksProvider.overrideWith((ref) => Stream.value(const [])),
          bookshelvesProvider.overrideWith((ref) => Stream.value(const [])),
          tagsProvider.overrideWith((ref) => Stream.value(const [])),
          readingProgressesProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          bookshelfEntriesProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
        child: const LeeefApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('书库'), findsNWidgets(2));
    expect(find.text('开始你的书库'), findsOneWidget);
    expect(find.text('导入书籍'), findsOneWidget);
  });

  testWidgets('English locale localizes the primary library experience', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'leeef.appearance.locale': 'en',
      'leeef.onboarding.completed': true,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryBooksProvider.overrideWith((ref) => Stream.value(const [])),
          bookshelvesProvider.overrideWith((ref) => Stream.value(const [])),
          tagsProvider.overrideWith((ref) => Stream.value(const [])),
          readingProgressesProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          bookshelfEntriesProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
        child: const LeeefApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Library'), findsNWidgets(2));
    expect(find.text('Start your library'), findsOneWidget);
    expect(find.text('Import books'), findsOneWidget);
  });

  testWidgets('library grid uses cover tiles instead of material cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'leeef.appearance.locale': 'zh',
      'leeef.onboarding.completed': true,
    });
    final now = DateTime.utc(2026, 1, 1);
    final book = BookRecord(
      id: 'book-1',
      sha256: 'a' * 64,
      title: '月光下的阅读',
      author: 'Leeef',
      mediaType: 'application/epub+zip',
      isAvailableLocally: true,
      isDeleted: false,
      createdAt: now,
      updatedAt: now,
    );
    final shelf = BookshelfRecord(
      id: 'shelf-1',
      name: '待读',
      sortOrder: 0,
      isDeleted: false,
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryBooksProvider.overrideWith((ref) => Stream.value([book])),
          bookshelvesProvider.overrideWith((ref) => Stream.value([shelf])),
          tagsProvider.overrideWith((ref) => Stream.value(const [])),
          readingProgressesProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          bookshelfEntriesProvider.overrideWith(
            (ref) => Stream.value([
              BookshelfEntry(
                bookshelfId: 'shelf-1',
                bookId: 'book-1',
                sortOrder: 0,
                updatedAt: now,
              ),
            ]),
          ),
        ],
        child: const LeeefApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(BookshelfFolderTile), findsOneWidget);
    expect(find.text('待读'), findsOneWidget);
    expect(find.byType(BookshelfBookTile), findsNothing);
    expect(find.byType(BookshelfImportTile), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
