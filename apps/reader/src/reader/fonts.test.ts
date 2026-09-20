import { describe, expect, it } from 'vitest'
import { DEFAULT_FONT_ID, READING_FONTS, resolveFont, shouldOverrideBookFont } from './fonts'

describe('resolveFont', () => {
  it('defaults to Source Han / Noto Serif SC', () => {
    expect(resolveFont().id).toBe(DEFAULT_FONT_ID)
    expect(resolveFont('').family).toBe('Noto Serif SC')
  })

  it('accepts catalog ids and family names', () => {
    expect(resolveFont('lxgw-wenkai').label).toBe('霞鹜文楷')
    expect(resolveFont('Noto Sans SC').id).toBe('noto-sans-sc')
  })

  it('passes through unknown CSS stacks', () => {
    const custom = resolveFont('Palatino, serif')
    expect(custom.id).toBe('custom')
    expect(custom.stack).toBe('Palatino, serif')
    expect(shouldOverrideBookFont(custom)).toBe(true)
  })

  it('does not override publisher faces', () => {
    expect(shouldOverrideBookFont(resolveFont('publisher'))).toBe(false)
    expect(READING_FONTS.some((font) => font.files.length > 0)).toBe(true)
  })
})
