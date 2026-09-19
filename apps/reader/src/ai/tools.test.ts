import { describe, expect, it, vi } from 'vitest'
import type { Book, Excerpt, Session } from '../api'
import { bookSummary, clampLimit, DEFAULT_TAG_COLOR, matchesQuery } from './library'
import { createLeeefToolActions, WRITE_TOOL_NAMES } from './tools'
import type { LeeefLibrary } from './library'

const book = (overrides: Partial<Book> = {}): Book => ({
  id: 'b1',
  sha256: 'abc',
  title: '大奉打更人',
  author: '卖报小郎君',
  description: '玄幻',
  mediaType: 'application/epub+zip',
  filePath: '/secret/path.epub',
  coverPath: '/secret/cover.jpg',
  rating: 5,
  isAvailableLocally: true,
  createdAt: '2026-01-01',
  updatedAt: '2026-01-01',
  progress: 0.4,
  locator: 'epubcfi(/6/2)',
  chapterTitle: '第一章',
  tags: ['玄幻'],
  shelfIds: [],
  ...overrides,
})

function fakeLibrary(overrides: Partial<LeeefLibrary> = {}): LeeefLibrary {
  return {
    listBooks: vi.fn(async () => [book(), book({ id: 'b2', title: '三体', author: '刘慈欣' })]),
    updateBook: vi.fn(async () => undefined),
    deleteBook: vi.fn(async () => undefined),
    saveProgress: vi.fn(async () => undefined),
    listExcerpts: vi.fn(async () => [] as Excerpt[]),
    createExcerpt: vi.fn(async () => undefined),
    deleteExcerpt: vi.fn(async () => undefined),
    listBookmarks: vi.fn(async () => []),
    addBookmark: vi.fn(async () => undefined),
    deleteBookmark: vi.fn(async () => undefined),
    listShelves: vi.fn(async () => [{ id: 's1', name: '在读', sortOrder: 0 }]),
    createShelf: vi.fn(async () => undefined),
    addBookToShelf: vi.fn(async () => undefined),
    removeBookFromShelf: vi.fn(async () => undefined),
    listTags: vi.fn(async () => []),
    createTag: vi.fn(async () => undefined),
    setBookTag: vi.fn(async () => undefined),
    listSessions: vi.fn(async () => [] as Session[]),
    ...overrides,
  }
}

describe('helpers', () => {
  it('clamps tool result limits', () => {
    expect(clampLimit(undefined)).toBe(50)
    expect(clampLimit(0)).toBe(1)
    expect(clampLimit(999)).toBe(200)
    expect(clampLimit(Number.NaN)).toBe(50)
  })

  it('omits local file paths from book summaries', () => {
    const summary = bookSummary(book())
    expect(summary).toMatchObject({ id: 'b1', title: '大奉打更人', progress: 0.4 })
    expect(summary).not.toHaveProperty('filePath')
    expect(summary).not.toHaveProperty('coverPath')
    expect(summary).not.toHaveProperty('sha256')
  })

  it('matches case-insensitive queries', () => {
    expect(matchesQuery('大奉打更人 卖报小郎君', '打更')).toBe(true)
    expect(matchesQuery('Hello World', 'hello')).toBe(true)
    expect(matchesQuery('Hello', '  ')).toBe(true)
    expect(matchesQuery('Hello', 'xyz')).toBe(false)
  })
})

describe('createLeeefTools', () => {
  it('exposes read tools that do not require write approval', () => {
    expect(WRITE_TOOL_NAMES.has('list_books')).toBe(false)
    expect(WRITE_TOOL_NAMES.has('delete_book')).toBe(true)
    expect(WRITE_TOOL_NAMES.has('update_reading_progress')).toBe(true)
  })

  it('lists and searches books through the library port', async () => {
    const library = fakeLibrary()
    const actions = createLeeefToolActions(library)
    const listed = await actions.list_books({ limit: 1 })
    expect(listed.total).toBe(2)
    expect(listed.books).toHaveLength(1)
    expect(listed.books[0]?.title).toBe('大奉打更人')

    const found = await actions.search_books({ query: '三体' })
    expect(found.books.map((item) => item.id)).toEqual(['b2'])
  })

  it('applies write tools after confirmation via the library port', async () => {
    const library = fakeLibrary()
    const actions = createLeeefToolActions(library)
    await actions.delete_book({ bookId: 'b1' })
    await actions.create_tag({ name: '想读' })
    expect(library.deleteBook).toHaveBeenCalledWith('b1')
    expect(library.createTag).toHaveBeenCalledWith('想读', DEFAULT_TAG_COLOR)
  })
})
