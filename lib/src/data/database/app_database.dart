import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'app_database.g.dart';

@DataClassName('BookRecord')
class Books extends Table {
  TextColumn get id => text()();
  TextColumn get sha256 => text().withLength(min: 64, max: 64).unique()();
  TextColumn get md5 => text().withLength(min: 32, max: 32).nullable()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get mediaType => text()();
  TextColumn get filePath => text().nullable()();
  TextColumn get coverPath => text().nullable()();
  TextColumn get coverSha256 => text().nullable()();
  RealColumn get rating => real().nullable()();
  BoolColumn get isAvailableLocally =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TagRecord')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get color => integer()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class BookTagEntries extends Table {
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {tagId, bookId};
}

@DataClassName('BookshelfRecord')
class Bookshelves extends Table {
  TextColumn get id => text()();
  TextColumn get parentId => text().nullable().references(
    Bookshelves,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class BookshelfEntries extends Table {
  TextColumn get bookshelfId =>
      text().references(Bookshelves, #id, onDelete: KeyAction.cascade)();
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {bookshelfId, bookId};
}

@DataClassName('ExcerptRecord')
class Excerpts extends Table {
  TextColumn get id => text()();
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get locator => text()();
  TextColumn get quote => text()();
  TextColumn get note => text().nullable()();
  TextColumn get color => text().withDefault(const Constant('yellow'))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('BookmarkRecord')
class Bookmarks extends Table {
  TextColumn get id => text()();
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get locator => text()();
  TextColumn get title => text().nullable()();
  TextColumn get note => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ReadingProgressRecord')
class ReadingProgresses extends Table {
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get locator => text()();
  RealColumn get progress => real()();
  TextColumn get chapterTitle => text().nullable()();
  IntColumn get page => integer().nullable()();
  TextColumn get deviceId => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {bookId};
}

@DataClassName('ReadingProgressHistoryRecord')
class ReadingProgressHistory extends Table {
  TextColumn get operationId => text()();
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get locator => text()();
  RealColumn get progress => real()();
  TextColumn get chapterTitle => text().nullable()();
  IntColumn get page => integer().nullable()();
  TextColumn get deviceId => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {operationId};
}

@DataClassName('ReadingSessionRecord')
class ReadingSessions extends Table {
  TextColumn get id => text()();
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get deviceId => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime()();
  IntColumn get durationSeconds => integer()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SyncOperationRecord')
class SyncOperations extends Table {
  TextColumn get operationId => text()();
  TextColumn get deviceId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get kind => text()();
  TextColumn get payloadJson => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get appliedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {operationId};
}

@DataClassName('AuditEventRecord')
class AuditEvents extends Table {
  TextColumn get id => text()();
  TextColumn get caller => text()();
  TextColumn get action => text()();
  TextColumn get parametersJson => text()();
  TextColumn get result => text()();
  DateTimeColumn get occurredAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Books,
    Tags,
    BookTagEntries,
    Bookshelves,
    BookshelfEntries,
    Excerpts,
    Bookmarks,
    ReadingProgresses,
    ReadingProgressHistory,
    ReadingSessions,
    SyncOperations,
    AuditEvents,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase()
    : super(
        driftDatabase(
          name: 'leeef',
          native: DriftNativeOptions(databaseDirectory: _databaseDirectory),
        ),
      );

  AppDatabase.forTesting(super.executor);

  Future<File> copyToDirectory(Directory destination) async {
    await destination.create(recursive: true);
    final target = File('${destination.path}/leeef.sqlite');
    if (await target.exists()) {
      throw StateError('目标目录已存在 leeef.sqlite，请选择空目录或先移走该文件。');
    }
    final escaped = target.path.replaceAll("'", "''");
    await customStatement("VACUUM INTO '$escaped'");
    return target;
  }

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) await migrator.createTable(readingProgressHistory);
      if (from < 3) {
        await migrator.addColumn(books, books.rating);
        await migrator.createTable(tags);
        await migrator.createTable(bookTagEntries);
      }
      if (from < 4) await migrator.addColumn(books, books.coverSha256);
      if (from < 5) await migrator.createTable(readingSessions);
      if (from < 6) await migrator.addColumn(books, books.md5);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

Future<Object> _databaseDirectory() async {
  final custom = (await SharedPreferences.getInstance()).getString(
    'leeef.storage.custom_directory',
  );
  if (custom != null && custom.trim().isNotEmpty) {
    final directory = Directory(custom);
    await directory.create(recursive: true);
    return directory;
  }
  return getApplicationDocumentsDirectory();
}
