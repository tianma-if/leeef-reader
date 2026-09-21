import type { Book, Excerpt } from '../api'

export type ExcerptExportFormat = 'markdown' | 'txt'

export type BookExcerptDocument = {
  bookId: string
  title: string
  author?: string | null
  excerpts: Excerpt[]
}

const normalizeNewlines = (value: string) => value.replace(/\r\n?/g, '\n')

const trimOuterBlankLines = (value: string) =>
  normalizeNewlines(value).replace(/^\n+|\n+$/g, '')

const markdownQuote = (value: string) =>
  trimOuterBlankLines(value)
    .split('\n')
    .map((line) => (line ? `> ${line}` : '>'))
    .join('\n')

export const excerptDate = (value: string) => {
  const date = /^\d{10}$/.test(value) ? new Date(Number(value) * 1000) : new Date(value)
  return Number.isNaN(date.valueOf()) ? value : date.toISOString().slice(0, 10)
}

const ordered = (excerpts: Excerpt[]) =>
  [...excerpts].sort((left, right) => left.createdAt.localeCompare(right.createdAt))

export function groupExcerptsByBook(excerpts: Excerpt[], books: Book[]): BookExcerptDocument[] {
  const booksById = new Map(books.map((book) => [book.id, book]))
  const grouped = new Map<string, Excerpt[]>()
  for (const excerpt of excerpts) {
    const group = grouped.get(excerpt.bookId)
    if (group) group.push(excerpt)
    else grouped.set(excerpt.bookId, [excerpt])
  }

  return [...grouped.entries()]
    .map(([bookId, items]) => {
      const book = booksById.get(bookId)
      return {
        bookId,
        title: book?.title ?? items[0]?.bookTitle ?? '未命名书籍',
        author: book?.author,
        excerpts: ordered(items),
      }
    })
    .sort((left, right) => left.title.localeCompare(right.title))
}

export function bookExcerptMarkdown(document: BookExcerptDocument): string {
  const lines = [`# ${document.title}`]
  if (document.author) lines.push('', `作者：${document.author}`)
  lines.push('', `书摘：${document.excerpts.length} 条`)

  for (const [index, excerpt] of ordered(document.excerpts).entries()) {
    lines.push('', `## 书摘 ${index + 1}`, '', markdownQuote(excerpt.quote))
    if (excerpt.note) {
      lines.push('', '**笔记**', '', trimOuterBlankLines(excerpt.note))
    }
    lines.push('', `— 摘录于 ${excerptDate(excerpt.createdAt)}`)
  }

  return `${lines.join('\n')}\n`
}

export function bookExcerptText(document: BookExcerptDocument): string {
  const lines = [document.title]
  if (document.author) lines.push(`作者：${document.author}`)
  lines.push(`书摘：${document.excerpts.length} 条`)

  for (const [index, excerpt] of ordered(document.excerpts).entries()) {
    lines.push('', `【书摘 ${index + 1}】`, trimOuterBlankLines(excerpt.quote))
    if (excerpt.note) lines.push('', '笔记：', trimOuterBlankLines(excerpt.note))
    lines.push('', `— 摘录于 ${excerptDate(excerpt.createdAt)}`)
  }

  return `${lines.join('\n')}\n`
}

export function excerptExportContent(
  documents: BookExcerptDocument[],
  format: ExcerptExportFormat,
): string {
  const separator = format === 'markdown' ? '\n\n---\n\n' : '\n\n====================\n\n'
  const render = format === 'markdown' ? bookExcerptMarkdown : bookExcerptText
  return documents.map((document) => render(document).trimEnd()).join(separator) + '\n'
}

export function safeExportFilename(title: string, format: ExcerptExportFormat): string {
  const basename = title
    .normalize('NFKC')
    .replace(/[\\/:*?"<>|\u0000-\u001f]/g, '_')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 100) || '书摘'
  return `${basename}-书摘.${format === 'markdown' ? 'md' : 'txt'}`
}
