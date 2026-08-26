import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/ai/ai_tool_registry.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/repositories/library_repository.dart';

void main() {
  test('parses only supported structured tool plans', () {
    final plan = AiToolPlan.parse('''
说明
```leeef-tool
{"tool":"create_bookshelf","arguments":{"name":"待读"},"summary":"创建待读书架"}
```
''');
    expect(plan?.tool, 'create_bookshelf');
    expect(plan?.arguments['name'], '待读');
    expect(AiToolPlan.parse('{"tool":"run_shell","arguments":{}}'), isNull);
  });

  test(
    'executes a confirmed plan through repository and records audit',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      var id = 0;
      final repository = LibraryRepository(
        database: database,
        deviceId: 'device',
        idGenerator: () => 'id-${id++}',
      );
      final plan = const AiToolPlan(
        tool: 'create_bookshelf',
        arguments: {'name': 'AI 整理'},
        summary: '创建书架',
      );

      final result = await const AiToolRegistry().execute(plan, repository);

      expect(result['status'], 'applied');
      expect((await repository.watchBookshelves().first).single.name, 'AI 整理');
      expect(await database.select(database.auditEvents).get(), hasLength(1));
      expect(
        (await database.select(database.syncOperations).get()),
        hasLength(1),
      );
    },
  );

  test(
    'executes permission-scoped read tools with structured results',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      var id = 0;
      final repository = LibraryRepository(
        database: database,
        deviceId: 'device',
        idGenerator: () => 'read-${id++}',
      );
      final bookId = await repository.createBookMetadata(
        sha256: List.filled(64, 'a').join(),
        title: 'The Green Library',
        author: 'Leeef Team',
        mediaType: 'text/plain',
      );
      await repository.createExcerpt(
        bookId: bookId,
        locator: 'txt:0',
        quote: 'A searchable passage',
      );

      final books = await const AiToolRegistry().executeRead(
        const AiToolPlan(
          tool: 'search_books',
          arguments: {'query': 'green'},
          summary: 'search',
        ),
        repository,
      );
      final excerpts = await const AiToolRegistry().executeRead(
        const AiToolPlan(
          tool: 'search_excerpts',
          arguments: {'query': 'searchable'},
          summary: 'search notes',
        ),
        repository,
      );

      expect(books['books'], hasLength(1));
      expect(excerpts['excerpts'], hasLength(1));
      expect(
        const AiToolPermissions(library: false).allows(
          const AiToolPlan(tool: 'search_books', arguments: {}, summary: ''),
        ),
        isFalse,
      );
    },
  );

  test(
    'supports the complete bookshelf, tag, and bookmark write surface',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      var id = 0;
      final repository = LibraryRepository(
        database: database,
        deviceId: 'device',
        idGenerator: () => 'write-${id++}',
      );
      final bookId = await repository.createBookMetadata(
        sha256: List.filled(64, 'b').join(),
        title: 'Tool Book',
        mediaType: 'text/plain',
      );
      final registry = const AiToolRegistry();
      final shelf = await registry.execute(
        const AiToolPlan(
          tool: 'create_bookshelf',
          arguments: {'name': 'AI Shelf'},
          summary: '',
        ),
        repository,
      );
      final tag = await registry.execute(
        const AiToolPlan(
          tool: 'create_tag',
          arguments: {'name': 'AI Tag', 'color': '#336699'},
          summary: '',
        ),
        repository,
      );
      await registry.execute(
        AiToolPlan(
          tool: 'add_book_to_bookshelf',
          arguments: {'bookId': bookId, 'bookshelfId': shelf['entityId']},
          summary: '',
        ),
        repository,
      );
      await registry.execute(
        AiToolPlan(
          tool: 'add_book_tag',
          arguments: {'bookId': bookId, 'tagId': tag['entityId']},
          summary: '',
        ),
        repository,
      );
      await registry.execute(
        AiToolPlan(
          tool: 'create_bookmark',
          arguments: {
            'bookId': bookId,
            'locator': 'txt:12',
            'title': 'AI bookmark',
          },
          summary: '',
        ),
        repository,
      );

      expect(await repository.listBookBookshelfIds(bookId), hasLength(1));
      expect(await repository.listBookTagIds(bookId), hasLength(1));
      expect(
        await repository.watchBookmarks(bookId: bookId).first,
        hasLength(1),
      );
    },
  );
}
