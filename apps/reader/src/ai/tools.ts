import { tool } from 'ai'
import { z } from 'zod'
import {
  bookSummary,
  clampLimit,
  DEFAULT_TAG_COLOR,
  matchesQuery,
  type LeeefLibrary,
} from './library'

const limitField = z.number().int().min(1).max(200).optional()

export const WRITE_TOOL_NAMES = new Set([
  'update_book_metadata',
  'delete_book',
  'create_bookshelf',
  'add_book_to_bookshelf',
  'remove_book_from_bookshelf',
  'create_tag',
  'add_book_tag',
  'remove_book_tag',
  'create_excerpt',
  'delete_excerpt',
  'create_bookmark',
  'delete_bookmark',
  'update_reading_progress',
])

export const TOOL_LABELS: Record<string, string> = {
  list_books: '列出书库',
  search_books: '搜索书籍',
  list_bookshelves: '列出书架',
  list_tags: '列出标签',
  search_excerpts: '搜索书摘',
  list_bookmarks: '列出书签',
  list_reading_history: '阅读记录',
  get_reading_progress: '阅读进度',
  update_book_metadata: '更新书籍信息',
  delete_book: '删除书籍',
  create_bookshelf: '创建书架',
  add_book_to_bookshelf: '加入书架',
  remove_book_from_bookshelf: '移出书架',
  create_tag: '创建标签',
  add_book_tag: '给书打标签',
  remove_book_tag: '移除标签',
  create_excerpt: '添加书摘',
  delete_excerpt: '删除书摘',
  create_bookmark: '添加书签',
  delete_bookmark: '删除书签',
  update_reading_progress: '更新进度',
}

export function createLeeefToolActions(library: LeeefLibrary) {
  return {
    list_books: async ({ limit }: { limit?: number }) => {
      const books = await library.listBooks()
      const capped = clampLimit(limit)
      return { total: books.length, books: books.slice(0, capped).map(bookSummary) }
    },
    search_books: async ({ query, limit }: { query: string; limit?: number }) => {
      const books = (await library.listBooks()).filter((book) =>
        matchesQuery(`${book.title} ${book.author ?? ''} ${book.description ?? ''}`, query),
      )
      return { books: books.slice(0, clampLimit(limit)).map(bookSummary) }
    },
    list_bookshelves: async () => ({ bookshelves: await library.listShelves() }),
    list_tags: async () => ({ tags: await library.listTags() }),
    search_excerpts: async ({
      query,
      bookId,
      limit,
    }: {
      query?: string
      bookId?: string
      limit?: number
    }) => {
      const excerpts = (await library.listExcerpts(bookId)).filter((item) =>
        matchesQuery(`${item.quote} ${item.note ?? ''} ${item.bookTitle ?? ''}`, query ?? ''),
      )
      return { excerpts: excerpts.slice(0, clampLimit(limit)) }
    },
    list_bookmarks: async ({ bookId, limit }: { bookId: string; limit?: number }) => {
      const bookmarks = await library.listBookmarks(bookId)
      return { bookmarks: bookmarks.slice(0, clampLimit(limit)) }
    },
    list_reading_history: async ({ bookId, limit }: { bookId?: string; limit?: number }) => {
      const sessions = (await library.listSessions()).filter(
        (item) => !bookId || item.bookId === bookId,
      )
      return { sessions: sessions.slice(0, clampLimit(limit)) }
    },
    get_reading_progress: async ({ bookId }: { bookId: string }) => {
      const book = (await library.listBooks()).find((item) => item.id === bookId)
      if (!book) return { progress: null }
      return {
        progress: {
          bookId: book.id,
          title: book.title,
          locator: book.locator ?? null,
          progress: book.progress,
          chapterTitle: book.chapterTitle ?? null,
        },
      }
    },
    update_book_metadata: async ({
      bookId,
      title,
      author,
      rating,
    }: {
      bookId: string
      title?: string
      author?: string
      rating?: number
    }) => {
      await library.updateBook(bookId, title, author, rating)
      return { tool: 'update_book_metadata', entityId: bookId, status: 'applied' as const }
    },
    delete_book: async ({ bookId }: { bookId: string }) => {
      await library.deleteBook(bookId)
      return { tool: 'delete_book', entityId: bookId, status: 'applied' as const }
    },
    create_bookshelf: async ({ name, parentId }: { name: string; parentId?: string }) => {
      await library.createShelf(name, parentId)
      return {
        tool: 'create_bookshelf',
        name,
        parentId: parentId ?? null,
        status: 'applied' as const,
      }
    },
    add_book_to_bookshelf: async ({
      bookId,
      bookshelfId,
    }: {
      bookId: string
      bookshelfId: string
    }) => {
      await library.addBookToShelf(bookshelfId, bookId)
      return { tool: 'add_book_to_bookshelf', entityId: bookId, status: 'applied' as const }
    },
    remove_book_from_bookshelf: async ({
      bookId,
      bookshelfId,
    }: {
      bookId: string
      bookshelfId: string
    }) => {
      await library.removeBookFromShelf(bookshelfId, bookId)
      return { tool: 'remove_book_from_bookshelf', entityId: bookId, status: 'applied' as const }
    },
    create_tag: async ({ name, color }: { name: string; color?: number }) => {
      await library.createTag(name, color ?? DEFAULT_TAG_COLOR)
      return { tool: 'create_tag', name, status: 'applied' as const }
    },
    add_book_tag: async ({ bookId, tagId }: { bookId: string; tagId: string }) => {
      await library.setBookTag(bookId, tagId, true)
      return { tool: 'add_book_tag', entityId: bookId, status: 'applied' as const }
    },
    remove_book_tag: async ({ bookId, tagId }: { bookId: string; tagId: string }) => {
      await library.setBookTag(bookId, tagId, false)
      return { tool: 'remove_book_tag', entityId: bookId, status: 'applied' as const }
    },
    create_excerpt: async ({
      bookId,
      locator,
      quote,
      note,
      color,
    }: {
      bookId: string
      locator: string
      quote: string
      note?: string
      color?: string
    }) => {
      await library.createExcerpt({
        bookId,
        locator,
        quote,
        note,
        color: color ?? 'yellow',
      })
      return { tool: 'create_excerpt', entityId: bookId, status: 'applied' as const }
    },
    delete_excerpt: async ({ excerptId }: { excerptId: string }) => {
      await library.deleteExcerpt(excerptId)
      return { tool: 'delete_excerpt', entityId: excerptId, status: 'applied' as const }
    },
    create_bookmark: async ({
      bookId,
      locator,
      title,
    }: {
      bookId: string
      locator: string
      title?: string
    }) => {
      await library.addBookmark(bookId, locator, title)
      return { tool: 'create_bookmark', entityId: bookId, status: 'applied' as const }
    },
    delete_bookmark: async ({ bookmarkId }: { bookmarkId: string }) => {
      await library.deleteBookmark(bookmarkId)
      return { tool: 'delete_bookmark', entityId: bookmarkId, status: 'applied' as const }
    },
    update_reading_progress: async ({
      bookId,
      locator,
      progress,
      chapterTitle,
    }: {
      bookId: string
      locator: string
      progress: number
      chapterTitle?: string
    }) => {
      await library.saveProgress(bookId, locator, progress, chapterTitle)
      return { tool: 'update_reading_progress', entityId: bookId, status: 'applied' as const }
    },
  }
}

export function createLeeefTools(library: LeeefLibrary) {
  const actions = createLeeefToolActions(library)
  return {
    list_books: tool({
      description: 'List books in the Leeef library.',
      inputSchema: z.object({ limit: limitField }),
      execute: actions.list_books,
    }),
    search_books: tool({
      description: 'Search books by title, author, or description.',
      inputSchema: z.object({
        query: z.string().describe('Case-insensitive substring to match'),
        limit: limitField,
      }),
      execute: actions.search_books,
    }),
    list_bookshelves: tool({
      description: 'List bookshelves.',
      inputSchema: z.object({}),
      execute: actions.list_bookshelves,
    }),
    list_tags: tool({
      description: 'List tags.',
      inputSchema: z.object({}),
      execute: actions.list_tags,
    }),
    search_excerpts: tool({
      description: 'Search excerpts/quotes. Optionally filter by book.',
      inputSchema: z.object({
        query: z.string().optional(),
        bookId: z.string().optional(),
        limit: limitField,
      }),
      execute: actions.search_excerpts,
    }),
    list_bookmarks: tool({
      description: 'List bookmarks for a book.',
      inputSchema: z.object({
        bookId: z.string(),
        limit: limitField,
      }),
      execute: actions.list_bookmarks,
    }),
    list_reading_history: tool({
      description: 'List recent reading sessions.',
      inputSchema: z.object({
        bookId: z.string().optional(),
        limit: limitField,
      }),
      execute: actions.list_reading_history,
    }),
    get_reading_progress: tool({
      description: 'Get the saved reading progress for a book.',
      inputSchema: z.object({ bookId: z.string() }),
      execute: actions.get_reading_progress,
    }),
    update_book_metadata: tool({
      description: 'Update a book title, author, or rating. Requires user confirmation.',
      inputSchema: z.object({
        bookId: z.string(),
        title: z.string().optional(),
        author: z.string().optional(),
        rating: z.number().min(0).max(5).optional(),
      }),
      execute: actions.update_book_metadata,
    }),
    delete_book: tool({
      description: 'Delete a book from the library. Requires user confirmation.',
      inputSchema: z.object({ bookId: z.string() }),
      execute: actions.delete_book,
    }),
    create_bookshelf: tool({
      description: 'Create a bookshelf. Requires user confirmation.',
      inputSchema: z.object({
        name: z.string(),
        parentId: z.string().optional(),
      }),
      execute: actions.create_bookshelf,
    }),
    add_book_to_bookshelf: tool({
      description: 'Add a book to a bookshelf. Requires user confirmation.',
      inputSchema: z.object({
        bookId: z.string(),
        bookshelfId: z.string(),
      }),
      execute: actions.add_book_to_bookshelf,
    }),
    remove_book_from_bookshelf: tool({
      description: 'Remove a book from a bookshelf. Requires user confirmation.',
      inputSchema: z.object({
        bookId: z.string(),
        bookshelfId: z.string(),
      }),
      execute: actions.remove_book_from_bookshelf,
    }),
    create_tag: tool({
      description: 'Create a tag. Requires user confirmation.',
      inputSchema: z.object({
        name: z.string(),
        color: z.number().int().optional(),
      }),
      execute: actions.create_tag,
    }),
    add_book_tag: tool({
      description: 'Attach a tag to a book. Requires user confirmation.',
      inputSchema: z.object({
        bookId: z.string(),
        tagId: z.string(),
      }),
      execute: actions.add_book_tag,
    }),
    remove_book_tag: tool({
      description: 'Detach a tag from a book. Requires user confirmation.',
      inputSchema: z.object({
        bookId: z.string(),
        tagId: z.string(),
      }),
      execute: actions.remove_book_tag,
    }),
    create_excerpt: tool({
      description: 'Create an excerpt/quote. Requires user confirmation.',
      inputSchema: z.object({
        bookId: z.string(),
        locator: z.string(),
        quote: z.string(),
        note: z.string().optional(),
        color: z.string().optional(),
      }),
      execute: actions.create_excerpt,
    }),
    delete_excerpt: tool({
      description: 'Delete an excerpt. Requires user confirmation.',
      inputSchema: z.object({ excerptId: z.string() }),
      execute: actions.delete_excerpt,
    }),
    create_bookmark: tool({
      description: 'Create a bookmark. Requires user confirmation.',
      inputSchema: z.object({
        bookId: z.string(),
        locator: z.string(),
        title: z.string().optional(),
      }),
      execute: actions.create_bookmark,
    }),
    delete_bookmark: tool({
      description: 'Delete a bookmark. Requires user confirmation.',
      inputSchema: z.object({ bookmarkId: z.string() }),
      execute: actions.delete_bookmark,
    }),
    update_reading_progress: tool({
      description: 'Update saved reading progress. Requires user confirmation.',
      inputSchema: z.object({
        bookId: z.string(),
        locator: z.string(),
        progress: z.number().min(0).max(1),
        chapterTitle: z.string().optional(),
      }),
      execute: actions.update_reading_progress,
    }),
  }
}

export type LeeefTools = ReturnType<typeof createLeeefTools>
