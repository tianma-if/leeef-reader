import 'dart:convert';

import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/repositories/library_repository.dart';
import 'package:leeef_reader/src/domain/reading_location.dart';

class AiToolPermissions {
  const AiToolPermissions({
    this.library = true,
    this.notes = true,
    this.history = true,
    this.write = false,
  });

  final bool library;
  final bool notes;
  final bool history;
  final bool write;

  bool allows(AiToolPlan plan) {
    if (!plan.isReadOnly) return write;
    return switch (plan.tool) {
      'list_books' ||
      'search_books' ||
      'list_bookshelves' ||
      'list_tags' => library,
      'search_excerpts' || 'list_bookmarks' => notes,
      'list_reading_history' || 'get_reading_progress' => history,
      _ => false,
    };
  }
}

class AiToolPlan {
  const AiToolPlan({
    required this.tool,
    required this.arguments,
    required this.summary,
  });

  final String tool;
  final Map<String, dynamic> arguments;
  final String summary;

  bool get isReadOnly => AiToolRegistry.readTools.contains(tool);

  static AiToolPlan? parse(String response) {
    final fenced = RegExp(
      r'```leeef-tool\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(response);
    final candidate = fenced?.group(1)?.trim() ?? response.trim();
    if (!candidate.startsWith('{')) return null;
    try {
      final value = jsonDecode(candidate);
      if (value is! Map) return null;
      final map = Map<String, dynamic>.from(value);
      final tool = map['tool'];
      final arguments = map['arguments'];
      if (tool is! String ||
          arguments is! Map ||
          !AiToolRegistry.supportedTools.contains(tool)) {
        return null;
      }
      return AiToolPlan(
        tool: tool,
        arguments: Map<String, dynamic>.from(arguments),
        summary: map['summary'] as String? ?? tool,
      );
    } on FormatException {
      return null;
    }
  }
}

class AiToolRegistry {
  const AiToolRegistry();

  static const readTools = {
    'list_books',
    'search_books',
    'list_bookshelves',
    'list_tags',
    'search_excerpts',
    'list_bookmarks',
    'list_reading_history',
    'get_reading_progress',
  };

  static const writeTools = {
    'update_book_metadata',
    'delete_book',
    'create_bookshelf',
    'rename_bookshelf',
    'move_bookshelf',
    'delete_bookshelf',
    'add_book_to_bookshelf',
    'remove_book_from_bookshelf',
    'create_tag',
    'update_tag',
    'delete_tag',
    'add_book_tag',
    'remove_book_tag',
    'create_excerpt',
    'update_excerpt',
    'delete_excerpt',
    'create_bookmark',
    'update_bookmark',
    'delete_bookmark',
    'update_reading_progress',
  };

  static const supportedTools = {...readTools, ...writeTools};

  static String systemInstructions(AiToolPermissions permissions) =>
      '''
You can query and manage Leeef Reader through structured tools. When a tool is
needed, return exactly one fenced `leeef-tool` JSON object with keys `tool`,
`arguments`, and `summary`. The app automatically executes allowed read tools
and supplies the result. Every write tool requires explicit user confirmation.

Allowed read schemas:
${permissions.library ? '- list_books: {limit?}\n- search_books: {query,limit?}\n- list_bookshelves: {}\n- list_tags: {}' : '- Library read tools are disabled.'}
${permissions.notes ? '- search_excerpts: {query,bookId?,limit?}\n- list_bookmarks: {bookId?,limit?}' : '- Notes read tools are disabled.'}
${permissions.history ? '- list_reading_history: {bookId?,limit?}\n- get_reading_progress: {bookId}' : '- Reading-history tools are disabled.'}

${permissions.write ? '''Allowed write schemas:
- update_book_metadata: {bookId,title?,author?,description?,rating?}
- delete_book: {bookId}
- create_bookshelf: {name,parentId?}
- rename_bookshelf: {bookshelfId,name}
- move_bookshelf: {bookshelfId,parentId?,sortOrder?}
- delete_bookshelf: {bookshelfId}
- add_book_to_bookshelf/remove_book_from_bookshelf: {bookId,bookshelfId}
- create_tag: {name,color?}
- update_tag: {tagId,name,color}
- delete_tag: {tagId}
- add_book_tag/remove_book_tag: {bookId,tagId}
- create_excerpt: {bookId,locator,quote,note?,color?}
- update_excerpt: {excerptId,note?,color?}
- delete_excerpt: {excerptId}
- create_bookmark: {bookId,locator,title?,note?}
- update_bookmark: {bookmarkId,title?,note?}
- delete_bookmark: {bookmarkId}
- update_reading_progress: {bookId,locator,progress,chapterTitle?,page?}''' : 'Write tools are disabled. Do not emit mutation plans.'}
Never claim a mutation succeeded before the app confirms it.
''';

  Future<Map<String, Object?>> executeRead(
    AiToolPlan plan,
    LibraryRepository repository,
  ) async {
    if (!plan.isReadOnly) {
      throw ArgumentError.value(plan.tool, 'tool', 'Tool is not read-only.');
    }
    final args = plan.arguments;
    final limit = _limit(args);
    switch (plan.tool) {
      case 'list_books':
        final books = await repository.listBooks();
        return {
          'books': [for (final book in books.take(limit)) _bookJson(book)],
          'total': books.length,
        };
      case 'search_books':
        final query = _string(args, 'query').toLowerCase();
        final books = (await repository.listBooks())
            .where(
              (book) =>
                  book.title.toLowerCase().contains(query) ||
                  (book.author?.toLowerCase().contains(query) ?? false) ||
                  (book.description?.toLowerCase().contains(query) ?? false),
            )
            .take(limit);
        return {
          'books': [for (final book in books) _bookJson(book)],
        };
      case 'list_bookshelves':
        final shelves = await repository.watchBookshelves().first;
        return {
          'bookshelves': [
            for (final shelf in shelves)
              {
                'id': shelf.id,
                'name': shelf.name,
                'parentId': shelf.parentId,
                'sortOrder': shelf.sortOrder,
              },
          ],
        };
      case 'list_tags':
        final tags = await repository.watchTags().first;
        return {
          'tags': [
            for (final tag in tags)
              {'id': tag.id, 'name': tag.name, 'color': tag.color},
          ],
        };
      case 'search_excerpts':
        final query = (args['query'] as String? ?? '').trim().toLowerCase();
        final excerpts =
            (await repository.listExcerpts(
              bookId: args['bookId'] as String?,
            )).where(
              (item) =>
                  query.isEmpty ||
                  item.quote.toLowerCase().contains(query) ||
                  (item.note?.toLowerCase().contains(query) ?? false),
            );
        return {
          'excerpts': [
            for (final item in excerpts.take(limit))
              {
                'id': item.id,
                'bookId': item.bookId,
                'locator': item.locator,
                'quote': item.quote,
                'note': item.note,
                'color': item.color,
              },
          ],
        };
      case 'list_bookmarks':
        final bookmarks = await repository
            .watchBookmarks(bookId: args['bookId'] as String?)
            .first;
        return {
          'bookmarks': [
            for (final item in bookmarks.take(limit))
              {
                'id': item.id,
                'bookId': item.bookId,
                'locator': item.locator,
                'title': item.title,
                'note': item.note,
              },
          ],
        };
      case 'list_reading_history':
        final bookId = args['bookId'] as String?;
        final sessions = (await repository.watchReadingSessions().first)
            .where((item) => bookId == null || item.bookId == bookId)
            .take(limit);
        return {
          'sessions': [
            for (final item in sessions)
              {
                'id': item.id,
                'bookId': item.bookId,
                'startedAt': item.startedAt.toIso8601String(),
                'endedAt': item.endedAt.toIso8601String(),
                'durationSeconds': item.durationSeconds,
              },
          ],
        };
      case 'get_reading_progress':
        final progress = await repository.getReadingProgress(
          _string(args, 'bookId'),
        );
        return {
          'progress': progress == null
              ? null
              : {
                  'bookId': progress.bookId,
                  'locator': progress.locator,
                  'progress': progress.progress,
                  'chapterTitle': progress.chapterTitle,
                  'page': progress.page,
                  'updatedAt': progress.updatedAt.toIso8601String(),
                },
        };
    }
    throw UnsupportedError(plan.tool);
  }

  Future<Map<String, Object?>> execute(
    AiToolPlan plan,
    LibraryRepository repository,
  ) async {
    if (plan.isReadOnly) return executeRead(plan, repository);
    final args = plan.arguments;
    Object? entityId;
    try {
      switch (plan.tool) {
        case 'update_book_metadata':
          final bookId = _string(args, 'bookId');
          final current = await repository.getBook(bookId);
          if (current == null) throw StateError('书籍不存在：$bookId');
          await repository.updateBookDetails(
            bookId: bookId,
            title: args['title'] as String? ?? current.title,
            author: args.containsKey('author')
                ? args['author'] as String?
                : current.author,
            description: args.containsKey('description')
                ? args['description'] as String?
                : current.description,
            rating: args.containsKey('rating')
                ? (args['rating'] as num?)?.toDouble()
                : current.rating,
          );
          entityId = bookId;
        case 'delete_book':
          entityId = _string(args, 'bookId');
          await repository.softDeleteBook(entityId as String);
        case 'create_bookshelf':
          entityId = await repository.createBookshelf(
            name: _string(args, 'name'),
            parentId: args['parentId'] as String?,
          );
        case 'rename_bookshelf':
          entityId = _string(args, 'bookshelfId');
          await repository.renameBookshelf(
            entityId as String,
            _string(args, 'name'),
          );
        case 'move_bookshelf':
          entityId = _string(args, 'bookshelfId');
          await repository.moveBookshelf(
            bookshelfId: entityId as String,
            parentId: args['parentId'] as String?,
            sortOrder: (args['sortOrder'] as num?)?.toInt(),
          );
        case 'delete_bookshelf':
          entityId = _string(args, 'bookshelfId');
          await repository.deleteBookshelf(entityId as String);
        case 'add_book_to_bookshelf':
          entityId = _string(args, 'bookId');
          await repository.addBookToBookshelf(
            bookId: entityId as String,
            bookshelfId: _string(args, 'bookshelfId'),
          );
        case 'remove_book_from_bookshelf':
          entityId = _string(args, 'bookId');
          await repository.removeBookFromBookshelf(
            bookId: entityId as String,
            bookshelfId: _string(args, 'bookshelfId'),
          );
        case 'create_tag':
          entityId = await repository.createTag(
            name: _string(args, 'name'),
            color: _color(args['color']),
          );
        case 'update_tag':
          entityId = _string(args, 'tagId');
          await repository.updateTag(
            tagId: entityId as String,
            name: _string(args, 'name'),
            color: _color(args['color']),
          );
        case 'delete_tag':
          entityId = _string(args, 'tagId');
          await repository.deleteTag(entityId as String);
        case 'add_book_tag':
          entityId = _string(args, 'bookId');
          await repository.addBookTag(
            bookId: entityId as String,
            tagId: _string(args, 'tagId'),
          );
        case 'remove_book_tag':
          entityId = _string(args, 'bookId');
          await repository.removeBookTag(
            bookId: entityId as String,
            tagId: _string(args, 'tagId'),
          );
        case 'create_excerpt':
          entityId = await repository.createExcerpt(
            bookId: _string(args, 'bookId'),
            locator: _string(args, 'locator'),
            quote: _string(args, 'quote'),
            note: args['note'] as String?,
            color: args['color'] as String? ?? 'yellow',
          );
        case 'update_excerpt':
          entityId = _string(args, 'excerptId');
          await repository.updateExcerpt(
            excerptId: entityId as String,
            note: args['note'] as String? ?? '',
            color: args['color'] as String? ?? 'yellow',
          );
        case 'delete_excerpt':
          entityId = _string(args, 'excerptId');
          await repository.deleteExcerpt(entityId as String);
        case 'create_bookmark':
          entityId = await repository.createBookmark(
            bookId: _string(args, 'bookId'),
            locator: _string(args, 'locator'),
            title: args['title'] as String?,
            note: args['note'] as String?,
          );
        case 'update_bookmark':
          entityId = _string(args, 'bookmarkId');
          await repository.updateBookmark(
            bookmarkId: entityId as String,
            title: args['title'] as String? ?? '',
            note: args['note'] as String? ?? '',
          );
        case 'delete_bookmark':
          entityId = _string(args, 'bookmarkId');
          await repository.deleteBookmark(entityId as String);
        case 'update_reading_progress':
          entityId = _string(args, 'bookId');
          await repository.updateReadingProgress(
            bookId: entityId as String,
            location: ReadingLocation(
              locator: _string(args, 'locator'),
              progress: _progress(args['progress']),
              chapterTitle: args['chapterTitle'] as String?,
              page: (args['page'] as num?)?.toInt(),
            ),
          );
        default:
          throw UnsupportedError(plan.tool);
      }
      await repository.recordAuditEvent(
        caller: 'ai-assistant',
        action: plan.tool,
        parameters: args,
        result: 'applied',
      );
      return {'tool': plan.tool, 'entityId': entityId, 'status': 'applied'};
    } on Object catch (error) {
      await repository.recordAuditEvent(
        caller: 'ai-assistant',
        action: plan.tool,
        parameters: args,
        result: 'failed: $error',
      );
      rethrow;
    }
  }

  static Map<String, Object?> _bookJson(BookRecord book) => {
    'id': book.id,
    'title': book.title,
    'author': book.author,
    'description': book.description,
    'rating': book.rating,
    'mediaType': book.mediaType,
    'availableLocally': book.isAvailableLocally,
  };

  static int _limit(Map<String, dynamic> args) =>
      ((args['limit'] as num?)?.toInt() ?? 50).clamp(1, 200);

  static int _color(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) {
      final normalized = value.replaceFirst('#', '');
      final parsed = int.tryParse(normalized, radix: 16);
      if (parsed != null) {
        return normalized.length <= 6 ? 0xFF000000 | parsed : parsed;
      }
    }
    return 0xFF4CAF50;
  }

  static double _progress(Object? value) {
    if (value is! num || value < 0 || value > 1) {
      throw const FormatException('progress 必须是 0 到 1 之间的数字。');
    }
    return value.toDouble();
  }

  static String _string(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('工具参数 $key 缺失或无效。');
    }
    return value.trim();
  }
}
