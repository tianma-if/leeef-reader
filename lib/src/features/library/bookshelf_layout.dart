import 'package:leeef_reader/src/data/database/app_database.dart';

/// Readest grid covers use a 28:41 book-cover frame.
const kBookshelfCoverAspectRatio = 28 / 41;

/// Title + progress row below each cover, matching Readest's `text-xs` + 15px icon row.
const kBookshelfTileMetaHeight = 44.0;

int bookshelfColumnCount(double width, {required bool compact}) {
  final extra = compact ? 1 : 0;
  if (width < 640) return 3 + extra;
  if (width < 768) return 4 + extra;
  if (width < 1280) return 6 + extra;
  if (width < 1536) return 8 + extra;
  return 12;
}

double bookshelfChildAspectRatio(double cellWidth) {
  final coverHeight = cellWidth / kBookshelfCoverAspectRatio;
  return cellWidth / (coverHeight + kBookshelfTileMetaHeight);
}

List<BookshelfRecord> childBookshelves({
  required List<BookshelfRecord> shelves,
  required String? parentId,
}) {
  final children = shelves
      .where((shelf) => shelf.parentId == parentId && !shelf.isDeleted)
      .toList();
  children.sort((left, right) {
    final order = left.sortOrder.compareTo(right.sortOrder);
    if (order != 0) return order;
    return left.name.toLowerCase().compareTo(right.name.toLowerCase());
  });
  return children;
}

Set<String> descendantBookIds({
  required String shelfId,
  required List<BookshelfRecord> shelves,
  required Map<String, List<String>> memberships,
}) {
  final ids = <String>{};
  void walk(String id) {
    ids.addAll(memberships[id] ?? const []);
    for (final child in shelves.where((shelf) => shelf.parentId == id)) {
      walk(child.id);
    }
  }

  walk(shelfId);
  return ids;
}

Set<String> booksInVisibleFolders({
  required List<BookshelfRecord> folders,
  required List<BookshelfRecord> shelves,
  required Map<String, List<String>> memberships,
}) {
  final ids = <String>{};
  for (final folder in folders) {
    ids.addAll(
      descendantBookIds(
        shelfId: folder.id,
        shelves: shelves,
        memberships: memberships,
      ),
    );
  }
  return ids;
}

List<BookRecord> mosaicBooks({
  required String shelfId,
  required List<BookshelfRecord> shelves,
  required Map<String, List<String>> memberships,
  required Map<String, BookRecord> booksById,
  int limit = 4,
}) {
  final result = <BookRecord>[];
  for (final id in descendantBookIds(
    shelfId: shelfId,
    shelves: shelves,
    memberships: memberships,
  )) {
    final book = booksById[id];
    if (book == null) continue;
    result.add(book);
    if (result.length >= limit) break;
  }
  return result;
}

Map<String, List<String>> groupBookshelfMemberships(
  Iterable<BookshelfEntry> entries,
) {
  final memberships = <String, List<String>>{};
  for (final entry in entries) {
    memberships.putIfAbsent(entry.bookshelfId, () => []).add(entry.bookId);
  }
  return memberships;
}
