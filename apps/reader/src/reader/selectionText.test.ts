import { describe, expect, it } from 'vitest'
import { normalizeSelectedText } from './selectionText'

describe('normalizeSelectedText', () => {
  it('normalizes line endings and preserves internal blank lines', () => {
    expect(normalizeSelectedText(' \r\n第一段\r\n\r\n第二段\r\n ')).toBe(
      '第一段\n\n第二段',
    )
  })
})
