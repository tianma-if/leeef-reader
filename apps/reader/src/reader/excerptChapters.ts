import { api, type Excerpt, type ExcerptChapter } from '../api'
import { labelOf } from './bookStyles'
import { loadBookSource, loadFoliate } from './bookSource'

export function excerptChapter(item?: TocItem | null): ExcerptChapter {
  const title = labelOf(item?.label).trim()
  return { key: title ? item?.href || String(item?.id ?? title) : '', title }
}

export async function cacheExcerptChapters(view: FoliateViewElement, bookId: string, excerpts: Excerpt[]) {
  const missing = new Set(excerpts.filter((excerpt) => !excerpt.chapter).map((excerpt) => excerpt.locator))
  if (!missing.size) return
  const chapters: [string, ExcerptChapter][] = []
  for (const locator of missing) {
    const item = view.book?.toc?.length ? await view.getTOCItemOf(locator) : undefined
    chapters.push([locator, excerptChapter(item)])
  }
  await api.cacheExcerptChapters(bookId, chapters)
}

export async function prepareEdgeEverExcerptChapters() {
  const [books, excerpts] = await Promise.all([api.listBooks(), api.listExcerpts()])
  const missingByBook = new Map<string, Excerpt[]>()
  for (const excerpt of excerpts) {
    if (excerpt.chapter) continue
    const missing = missingByBook.get(excerpt.bookId)
    if (missing) missing.push(excerpt)
    else missingByBook.set(excerpt.bookId, [excerpt])
  }
  for (const book of books) {
    const missing = missingByBook.get(book.id)
    if (!missing || !book.isAvailableLocally) continue
    const [source] = await Promise.all([loadBookSource(book), loadFoliate()]).catch(() => [])
    if (!source) continue
    const view = document.createElement('foliate-view')
    try {
      await view.open(source)
      await cacheExcerptChapters(view, book.id, missing)
    } catch (error) {
      console.warn('无法读取书摘的章节', error)
    } finally {
      view.close()
      await view.book?.destroy?.()
    }
  }
}
