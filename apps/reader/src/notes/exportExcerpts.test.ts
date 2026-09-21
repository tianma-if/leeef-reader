import { describe, expect, it } from 'vitest'
import type { Excerpt } from '../api'
import {
  bookExcerptMarkdown,
  bookExcerptText,
  excerptExportContent,
  safeExportFilename,
} from './exportExcerpts'

const excerpt = (quote: string, note?: string): Excerpt => ({
  id: 'excerpt-1',
  bookId: 'book-1',
  locator: 'epubcfi(/6/2)',
  quote,
  note,
  color: '#c4a35a',
  createdAt: '2026-09-21T08:00:00Z',
  bookTitle: '换行测试',
})

describe('excerpt export', () => {
  it('preserves paragraph and blank-line structure in Markdown block quotes', () => {
    const output = bookExcerptMarkdown({
      bookId: 'book-1',
      title: '换行测试',
      author: '作者',
      excerpts: [excerpt('第一段\r\n第二行\r\n\r\n第二段', '想法一\n想法二')],
    })

    expect(output).toContain('> 第一段\n> 第二行\n>\n> 第二段')
    expect(output).toContain('**笔记**\n\n想法一\n想法二')
  })

  it('preserves paragraph and blank-line structure in plain text', () => {
    const output = bookExcerptText({
      bookId: 'book-1',
      title: '换行测试',
      excerpts: [excerpt('第一段\n\n第二段')],
    })

    expect(output).toContain('【书摘 1】\n第一段\n\n第二段')
  })

  it('separates books without changing their internal line breaks', () => {
    const output = excerptExportContent(
      [
        { bookId: '1', title: '甲', excerpts: [excerpt('甲一\n甲二')] },
        { bookId: '2', title: '乙', excerpts: [excerpt('乙一\n乙二')] },
      ],
      'markdown',
    )

    expect(output).toContain('> 甲一\n> 甲二\n\n— 摘录于 2026-09-21\n\n---\n\n# 乙')
    expect(output).toContain('> 乙一\n> 乙二')
  })

  it('creates a filesystem-safe filename', () => {
    expect(safeExportFilename('  A/B: C  ', 'markdown')).toBe('A_B_ C-书摘.md')
  })

  it('renders the database Unix timestamp as a readable date', () => {
    const output = bookExcerptText({
      bookId: 'book-1',
      title: '时间测试',
      excerpts: [{ ...excerpt('正文'), createdAt: '1789948800' }],
    })

    expect(output).toContain('— 摘录于 2026-09-21')
  })
})
