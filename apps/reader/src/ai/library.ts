import { api, type Book } from '../api'

export type LeeefLibrary = Pick<
  typeof api,
  | 'listBooks'
  | 'updateBook'
  | 'deleteBook'
  | 'saveProgress'
  | 'listExcerpts'
  | 'createExcerpt'
  | 'deleteExcerpt'
  | 'listBookmarks'
  | 'addBookmark'
  | 'deleteBookmark'
  | 'listShelves'
  | 'createShelf'
  | 'addBookToShelf'
  | 'removeBookFromShelf'
  | 'listTags'
  | 'createTag'
  | 'setBookTag'
  | 'listSessions'
>

export const defaultLibrary: LeeefLibrary = api

export const DEFAULT_TAG_COLOR = 0xff4caf50

export function clampLimit(limit?: number, fallback = 50): number {
  const value = limit ?? fallback
  if (!Number.isFinite(value)) return fallback
  return Math.min(200, Math.max(1, Math.trunc(value)))
}

export function bookSummary(book: Book) {
  return {
    id: book.id,
    title: book.title,
    author: book.author ?? null,
    description: book.description ?? null,
    rating: book.rating ?? null,
    mediaType: book.mediaType,
    isAvailableLocally: book.isAvailableLocally,
    progress: book.progress,
    chapterTitle: book.chapterTitle ?? null,
    tags: book.tags,
  }
}

export function matchesQuery(haystack: string, query: string): boolean {
  const needle = query.trim().toLowerCase()
  if (!needle) return true
  return haystack.toLowerCase().includes(needle)
}
