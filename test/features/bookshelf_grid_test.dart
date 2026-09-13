import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/features/library/bookshelf_cover.dart';
import 'package:leeef_reader/src/features/library/bookshelf_layout.dart';
import 'package:leeef_reader/src/features/library/bookshelf_tiles.dart';

void main() {
  final now = DateTime.utc(2026, 1, 1);

  BookRecord book({
    required String id,
    required String title,
    String? author,
  }) => BookRecord(
    id: id,
    sha256: id.padRight(64, '0'),
    title: title,
    author: author,
    mediaType: 'application/epub+zip',
    isAvailableLocally: true,
    isDeleted: false,
    createdAt: now,
    updatedAt: now,
  );

  BookshelfRecord shelf({
    required String id,
    required String name,
    String? parentId,
    int sortOrder = 0,
  }) => BookshelfRecord(
    id: id,
    parentId: parentId,
    name: name,
    sortOrder: sortOrder,
    isDeleted: false,
    createdAt: now,
    updatedAt: now,
  );

  test('phone width uses three columns, compact adds one', () {
    expect(bookshelfColumnCount(390, compact: false), 3);
    expect(bookshelfColumnCount(390, compact: true), 4);
    expect(bookshelfColumnCount(800, compact: false), 6);
    expect(bookshelfColumnCount(1600, compact: false), 12);
  });

  test('root folders hide nested books from the ungrouped shelf', () {
    final shelves = [
      shelf(id: 'fiction', name: 'Fiction'),
      shelf(id: 'sf', name: 'SF', parentId: 'fiction'),
    ];
    final memberships = groupBookshelfMemberships([
      BookshelfEntry(
        bookshelfId: 'fiction',
        bookId: 'book-a',
        sortOrder: 0,
        updatedAt: now,
      ),
      BookshelfEntry(
        bookshelfId: 'sf',
        bookId: 'book-b',
        sortOrder: 0,
        updatedAt: now,
      ),
    ]);
    final folders = childBookshelves(shelves: shelves, parentId: null);
    expect(folders.map((item) => item.id), ['fiction']);
    expect(
      booksInVisibleFolders(
        folders: folders,
        shelves: shelves,
        memberships: memberships,
      ),
      {'book-a', 'book-b'},
    );
    expect(
      mosaicBooks(
        shelfId: 'fiction',
        shelves: shelves,
        memberships: memberships,
        booksById: {
          'book-a': book(id: 'book-a', title: 'A'),
          'book-b': book(id: 'book-b', title: 'B'),
        },
      ).map((item) => item.id),
      ['book-a', 'book-b'],
    );
  });

  testWidgets('cover fallback shows title and author instead of a card icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 176,
            child: BookshelfCover(title: '月光下的阅读', author: 'Leeef'),
          ),
        ),
      ),
    );
    expect(find.text('月光下的阅读'), findsOneWidget);
    expect(find.text('Leeef'), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_rounded), findsNothing);
  });

  testWidgets('book tile shows percent progress, not a bar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 140,
            height: 260,
            child: BookshelfBookTile(
              book: book(id: 'book-1', title: '把时间当作朋友', author: '李笑来'),
              coverFit: BoxFit.cover,
              progress: 0.42,
            ),
          ),
        ),
      ),
    );
    expect(find.text('把时间当作朋友'), findsWidgets);
    expect(find.text('42%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('folder tile renders a 2x2 cover mosaic', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 140,
            height: 260,
            child: BookshelfFolderTile(
              name: '待读',
              coverFit: BoxFit.cover,
              covers: [
                book(id: 'a', title: 'A'),
                book(id: 'b', title: 'B'),
                book(id: 'c', title: 'C'),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('待读'), findsOneWidget);
    expect(find.byType(BookshelfCover), findsNWidgets(3));
  });
}
