import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

@DataClassName('BookRecord')
class Books extends Table {
  TextColumn get id => text()();
  TextColumn get sha256 => text().withLength(min: 64, max: 64).unique()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get mediaType => text()();
  TextColumn get filePath => text().nullable()();
  TextColumn get coverPath => text().nullable()();
  BoolColumn get isAvailableLocally =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
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
    Bookshelves,
    BookshelfEntries,
    Excerpts,
    Bookmarks,
    ReadingProgresses,
    ReadingProgressHistory,
    SyncOperations,
    AuditEvents,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'leeef'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) await migrator.createTable(readingProgressHistory);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
