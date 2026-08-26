import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/repositories/library_repository.dart';
import 'package:leeef_reader/src/import/book_import_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  unawaited(
    database.customSelect('SELECT 1').get().then((_) async {
      final preferences = await SharedPreferences.getInstance();
      if (preferences.getBool('leeef.storage.database_restart_pending') ??
          false) {
        await preferences.remove('leeef.storage.database_restart_pending');
      }
    }),
  );
  ref.onDispose(() => unawaited(database.close()));
  return database;
});

final deviceIdProvider = FutureProvider<String>((ref) async {
  const key = 'leeef.device_id';
  final preferences = await SharedPreferences.getInstance();
  final existing = preferences.getString(key);
  if (existing != null && existing.isNotEmpty) return existing;
  final deviceId = const Uuid().v7();
  await preferences.setString(key, deviceId);
  return deviceId;
});

final libraryRepositoryProvider = FutureProvider<LibraryRepository>((
  ref,
) async {
  final deviceId = await ref.watch(deviceIdProvider.future);
  return LibraryRepository(
    database: ref.watch(appDatabaseProvider),
    deviceId: deviceId,
  );
});

final libraryBooksProvider = StreamProvider<List<BookRecord>>((ref) async* {
  final repository = await ref.watch(libraryRepositoryProvider.future);
  yield* repository.watchLibrary();
});

final bookExcerptsProvider = StreamProvider.family<List<ExcerptRecord>, String>(
  (ref, bookId) async* {
    final repository = await ref.watch(libraryRepositoryProvider.future);
    yield* repository.watchExcerpts(bookId: bookId);
  },
);

final allExcerptsProvider = StreamProvider<List<ExcerptRecord>>((ref) async* {
  final repository = await ref.watch(libraryRepositoryProvider.future);
  yield* repository.watchExcerpts();
});

final allBookmarksProvider = StreamProvider<List<BookmarkRecord>>((ref) async* {
  final repository = await ref.watch(libraryRepositoryProvider.future);
  yield* repository.watchBookmarks();
});

final bookBookmarksProvider =
    StreamProvider.family<List<BookmarkRecord>, String>((ref, bookId) async* {
      final repository = await ref.watch(libraryRepositoryProvider.future);
      yield* repository.watchBookmarks(bookId: bookId);
    });

final bookshelvesProvider = StreamProvider<List<BookshelfRecord>>((ref) async* {
  final repository = await ref.watch(libraryRepositoryProvider.future);
  yield* repository.watchBookshelves();
});

final tagsProvider = StreamProvider<List<TagRecord>>((ref) async* {
  final repository = await ref.watch(libraryRepositoryProvider.future);
  yield* repository.watchTags();
});

final tagBookIdsProvider = StreamProvider.family<List<String>, String>((
  ref,
  tagId,
) async* {
  final repository = await ref.watch(libraryRepositoryProvider.future);
  yield* repository.watchTagBookIds(tagId);
});

final readingProgressesProvider = StreamProvider<List<ReadingProgressRecord>>((
  ref,
) async* {
  final repository = await ref.watch(libraryRepositoryProvider.future);
  yield* repository.watchReadingProgresses();
});

final readingSessionsProvider = StreamProvider<List<ReadingSessionRecord>>((
  ref,
) async* {
  final repository = await ref.watch(libraryRepositoryProvider.future);
  yield* repository.watchReadingSessions();
});

final bookshelfBookIdsProvider = StreamProvider.family<List<String>, String>((
  ref,
  bookshelfId,
) async* {
  final repository = await ref.watch(libraryRepositoryProvider.future);
  yield* repository.watchBookshelfBookIds(bookshelfId);
});

final libraryDirectoryProvider = FutureProvider<Directory>((ref) async {
  final preferences = await SharedPreferences.getInstance();
  final custom = preferences.getString('leeef.storage.custom_directory');
  if (custom != null && custom.trim().isNotEmpty) {
    return Directory(custom);
  }
  final documents = await getApplicationDocumentsDirectory();
  return Directory('${documents.path}/leeef/books');
});

final bookImportServiceProvider = FutureProvider<BookImportService>((
  ref,
) async {
  final repository = await ref.watch(libraryRepositoryProvider.future);
  return BookImportService(
    repository: repository,
    libraryDirectory: await ref.watch(libraryDirectoryProvider.future),
  );
});
