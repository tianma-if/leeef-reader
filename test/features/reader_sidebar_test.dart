import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/features/reader/reader_chrome_scaffold.dart';
import 'package:leeef_reader/src/features/reader/reader_sidebar.dart';
import 'package:leeef_reader/src/reader/reader_engine.dart';

void main() {
  test('flattenReaderToc preserves nested order and depth', () {
    const toc = [
      ReaderTocItem(
        label: '第一讲 汉代',
        href: 'c1',
        children: [ReaderTocItem(label: '前言', href: 'c1a')],
      ),
      ReaderTocItem(label: '第二讲 唐代', href: 'c2'),
    ];
    final flat = flattenReaderToc(toc);
    expect(flat.map((item) => item.id), ['c1', 'c1a', 'c2']);
    expect(flat.map((item) => item.depth), [0, 1, 0]);
  });

  test('matchingTocId prefers an exact chapter label', () {
    const toc = [
      ReaderSidebarTocItem(id: 'c1', label: '第一讲 汉代', pageLabel: '11'),
      ReaderSidebarTocItem(id: 'c2', label: '第二讲 唐代', pageLabel: '49'),
    ];
    expect(matchingTocId(toc, '第一讲 汉代'), 'c1');
    expect(matchingTocIdByPage(toc, 15), 'c1');
    expect(matchingTocIdByPage(toc, 49), 'c2');
  });

  test(
    'readerTocDisplayRows inserts current position after the active chapter',
    () {
      const toc = [
        ReaderSidebarTocItem(id: 'c1', label: '第一讲 汉代', pageLabel: '11'),
        ReaderSidebarTocItem(id: 'c2', label: '第二讲 唐代', pageLabel: '49'),
      ];
      final rows = readerTocDisplayRows(
        toc: toc,
        currentTocId: 'c1',
        currentPageLabel: '15',
      );
      expect(rows, hasLength(3));
      expect((rows[0] as ReaderTocEntryRow).item.id, 'c1');
      expect((rows[1] as ReaderTocCurrentRow).pageLabel, '15');
      expect((rows[2] as ReaderTocEntryRow).item.id, 'c2');
    },
  );

  test('readerPageFractionLabel uses current/total when available', () {
    expect(
      readerPageFractionLabel(current: 15, total: 226, progress: 0.06),
      '15 / 226',
    );
    expect(readerPageFractionLabel(progress: 0.42), '42%');
  });

  testWidgets(
    'sidebar inserts a current-position row under the active chapter',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookExcerptsProvider.overrideWith(
              (ref, bookId) => Stream<List<ExcerptRecord>>.value(const []),
            ),
            bookBookmarksProvider.overrideWith(
              (ref, bookId) => Stream<List<BookmarkRecord>>.value(const []),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ReaderSidebar(
                bookId: 'book-1',
                bookTitle: '钱穆：中国历代政治得失',
                toc: const [
                  ReaderSidebarTocItem(
                    id: 'c1',
                    label: '第一讲 汉代',
                    pageLabel: '11',
                  ),
                  ReaderSidebarTocItem(
                    id: 'c2',
                    label: '第二讲 唐代',
                    pageLabel: '49',
                  ),
                ],
                currentTocId: 'c1',
                currentPageLabel: '15',
                tab: ReaderSidebarTab.toc,
                onTabChanged: (_) {},
                onOpenToc: (_) {},
                onOpenLocator: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('钱穆：中国历代政治得失'), findsOneWidget);
      expect(find.text('第一讲 汉代'), findsOneWidget);
      expect(find.byKey(const Key('reader-current-position')), findsOneWidget);
      expect(find.text('15'), findsWidgets);
      expect(find.byIcon(Icons.list), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    },
  );

  testWidgets('desktop scaffold pins the sidebar beside the page label', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookExcerptsProvider.overrideWith(
              (ref, bookId) => Stream<List<ExcerptRecord>>.value(const []),
            ),
            bookBookmarksProvider.overrideWith(
              (ref, bookId) => Stream<List<BookmarkRecord>>.value(const []),
            ),
          ],
          child: MaterialApp(
            home: ReaderChromeScaffold(
              sidebarVisible: true,
              sidebarPinned: true,
              chromeVisible: false,
              chapterTitle: '第一讲 汉代',
              pageLabel: '15 / 226',
              header: AppBar(title: const Text('hidden')),
              footer: const SizedBox.shrink(),
              sidebar: ReaderSidebar(
                bookId: 'book-1',
                bookTitle: '钱穆：中国历代政治得失',
                toc: const [
                  ReaderSidebarTocItem(
                    id: 'c1',
                    label: '第一讲 汉代',
                    pageLabel: '11',
                  ),
                ],
                currentTocId: 'c1',
                currentPageLabel: '15',
                tab: ReaderSidebarTab.toc,
                onTabChanged: (_) {},
                onOpenToc: (_) {},
                onOpenLocator: (_) {},
                pinned: true,
              ),
              body: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('reader-sidebar')), findsOneWidget);
      expect(find.byKey(const Key('reader-page-info')), findsOneWidget);
      expect(find.text('15 / 226'), findsOneWidget);
      expect(find.text('第一讲 汉代'), findsWidgets);
      expect(find.text('hidden'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('mobile sidebar is a rounded sheet and chrome hides page info', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookExcerptsProvider.overrideWith(
              (ref, bookId) => Stream<List<ExcerptRecord>>.value(const []),
            ),
            bookBookmarksProvider.overrideWith(
              (ref, bookId) => Stream<List<BookmarkRecord>>.value(const []),
            ),
          ],
          child: MaterialApp(
            home: ReaderChromeScaffold(
              sidebarVisible: true,
              sidebarPinned: false,
              chromeVisible: true,
              chapterTitle: '第一讲 汉代',
              pageLabel: '15 / 226',
              header: AppBar(title: const Text('chrome')),
              footer: const SizedBox.shrink(),
              sidebar: ReaderSidebar(
                bookId: 'book-1',
                bookTitle: '钱穆：中国历代政治得失',
                toc: const [
                  ReaderSidebarTocItem(
                    id: 'c1',
                    label: '第一讲 汉代',
                    pageLabel: '11',
                  ),
                ],
                currentTocId: 'c1',
                currentPageLabel: '15',
                tab: ReaderSidebarTab.toc,
                onTabChanged: (_) {},
                onOpenToc: (_) {},
                onOpenLocator: (_) {},
              ),
              body: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('reader-sidebar')), findsOneWidget);
      expect(find.byKey(const Key('reader-page-info')), findsNothing);
      expect(find.text('chrome'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
