import { describe, expect, it } from 'vitest'
import { applyViewLayout, bookCss, PAGE_MARGIN_PX, themeOf } from './bookStyles'

const fakeView = () => {
  const attrs = new Map<string, string>()
  const renderer = {
    setAttribute: (name: string, value: string) => {
      attrs.set(name, value)
    },
    removeAttribute: (name: string) => {
      attrs.delete(name)
    },
    setStyles: () => undefined,
  }
  const view = {
    renderer,
    setAttribute: (name: string, value: string) => {
      attrs.set(`view:${name}`, value)
    },
    removeAttribute: (name: string) => {
      attrs.delete(`view:${name}`)
    },
  }
  return { view: view as unknown as FoliateViewElement, attrs }
}

describe('bookCss', () => {
  it('injects paper colors and default type', () => {
    const css = bookCss({})
    expect(css).toContain('#292b29')
    expect(css).toContain('#fbf8f1')
    expect(css).toContain('18px')
    expect(css).toContain('1.65')
    expect(css).toContain('color-scheme: light')
    expect(css).toContain('Noto Serif SC')
    expect(css).toContain('font-family: inherit !important')
  })

  it('keeps publisher faces when 书籍原字体 is selected', () => {
    const css = bookCss({ fontFamily: 'publisher' })
    expect(css).not.toContain('font-family: inherit !important')
    expect(css).toContain('Georgia')
  })

  it('applies a bundled reading face', () => {
    const css = bookCss({ fontFamily: 'lxgw-wenkai' })
    expect(css).toContain('LXGW WenKai')
    expect(css).toContain('font-family: inherit !important')
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

describe('applyViewLayout', () => {
  it('uses a compact page margin on mobile', () => {
    const { view, attrs } = fakeView()
    applyViewLayout(view, { flow: 'paginated' }, true)
    expect(attrs.get('margin')).toBe(`${PAGE_MARGIN_PX.mobile}px`)
    expect(attrs.get('max-column-count')).toBe('1')
    expect(attrs.has('view:no-swipe')).toBe(true)
  })

  it('keeps the wider desktop page margin', () => {
    const { view, attrs } = fakeView()
    applyViewLayout(view, { flow: 'paginated', columns: 2 }, false)
    expect(attrs.get('margin')).toBe(`${PAGE_MARGIN_PX.desktop}px`)
    expect(attrs.get('max-column-count')).toBe('2')
    expect(attrs.has('animated')).toBe(true)
  })
})
