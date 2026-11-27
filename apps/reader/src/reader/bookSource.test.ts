import { strFromU8, unzipSync } from 'fflate'
import { afterEach, expect, it, vi } from 'vitest'
import { api, type Book } from '../api'
import { loadBookSource } from './bookSource'

afterEach(() => vi.restoreAllMocks())

it('opens a plain-text library book through the existing TXT-to-EPUB converter', async () => {
  const book = { id: 'text-book', title: 'Imported novel', mediaType: 'text/plain' } as Book
  const source = new TextEncoder().encode('Chapter 1\nImported from MCP')
  const bookBytes = vi.spyOn(api, 'bookBytes').mockResolvedValue(source)

  const file = await loadBookSource(book)

  expect(bookBytes).toHaveBeenCalledWith(book.id)
  expect(file.type).toBe('application/epub+zip')
  const entries = unzipSync(new Uint8Array(await file.arrayBuffer()))
  expect(strFromU8(entries['OEBPS/text/chap1.xhtml'])).toContain('Imported from MCP')
})
