import { describe, expect, it } from 'vitest'
import { bookCss, themeOf } from './bookStyles'

describe('bookCss', () => {
  it('injects paper colors and default type', () => {
    const css = bookCss({})
    expect(css).toContain('#292b29')
    expect(css).toContain('#fbf8f1')
    expect(css).toContain('18px')
    expect(css).toContain('1.65')
    expect(css).toContain('color-scheme: light')
  })

  it('uses night palette and dark color-scheme', () => {
    const css = bookCss({ theme: 'night', fontSize: 22, lineHeight: 1.8 })
    expect(css).toContain('#d6d6d6')
    expect(css).toContain('#121212')
    expect(css).toContain('22px')
    expect(css).toContain('1.8')
    expect(css).toContain('color-scheme: dark')
  })
})

describe('themeOf', () => {
  it('falls back to paper', () => {
    expect(themeOf({}).name).toBe('纸张')
    expect(themeOf({ theme: 'sepia' }).bg).toBe('#f4ecd8')
  })
})
