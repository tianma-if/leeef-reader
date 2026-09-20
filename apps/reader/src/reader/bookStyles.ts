import type { Settings } from '../api'
import { mountReadingFontOnView } from './fontLoader'
import { resolveFont, shouldOverrideBookFont } from './fonts'

export const THEMES = {
  paper: { fg: '#292b29', bg: '#fbf8f1', name: '纸张' },
  sepia: { fg: '#5b4636', bg: '#f4ecd8', name: '护眼' },
  night: { fg: '#d6d6d6', bg: '#121212', name: '夜间' },
} as const

export type ThemeName = keyof typeof THEMES

export const DEFAULT_FONT_SIZE = 18
export const DEFAULT_LINE_HEIGHT = 1.65
export const DEFAULT_FONT_FAMILY = 'noto-serif-sc'

export const themeOf = (settings: Settings) => THEMES[settings.theme ?? 'paper']

export const bookCss = (settings: Settings) => {
  const theme = themeOf(settings)
  const fontSize = settings.fontSize ?? DEFAULT_FONT_SIZE
  const lineHeight = settings.lineHeight ?? DEFAULT_LINE_HEIGHT
  const font = resolveFont(settings.fontFamily)
  const night = settings.theme === 'night'
  const override = shouldOverrideBookFont(font)
  return `
html {
  color-scheme: ${night ? 'dark' : 'light'};
}
body {
  color: ${theme.fg} !important;
  background: ${theme.bg} !important;
  font-size: ${fontSize}px !important;
  line-height: ${lineHeight} !important;
  font-family: ${font.stack} !important;
}
${
  override
    ? `body *:not(code):not(pre):not(kbd):not(samp) {
  font-family: inherit !important;
}
code, pre, kbd, samp {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace !important;
}`
    : ''
}
a { color: inherit; }
img, svg, video { max-width: 100%; }
`
}

export const applyViewLayout = (
  view: FoliateViewElement,
  settings: Settings,
  mobile: boolean,
) => {
  const renderer = view.renderer
  if (!renderer) return
  const flow = settings.flow ?? 'paginated'
  const paginated = flow === 'paginated'
  renderer.setAttribute('flow', flow)
  renderer.setAttribute('max-column-count', String(mobile ? 1 : (settings.columns ?? 1)))
  renderer.setAttribute('margin', '44px')
  renderer.setAttribute('max-block-size', '10000px')
  if (paginated && mobile) {
    renderer.setAttribute('max-inline-size', '10000')
    view.setAttribute('no-swipe', '')
    renderer.setAttribute('no-swipe', '')
    renderer.removeAttribute('animated')
  } else if (paginated) {
    view.removeAttribute('no-swipe')
    renderer.removeAttribute('no-swipe')
    renderer.setAttribute('animated', '')
  } else {
    view.removeAttribute('no-swipe')
    renderer.removeAttribute('no-swipe')
    renderer.removeAttribute('animated')
  }
  renderer.setStyles?.(bookCss(settings))
}

export const applyReadingFont = async (
  view: FoliateViewElement | null | undefined,
  settings: Settings,
) => {
  await mountReadingFontOnView(view, settings.fontFamily)
  view?.renderer?.setStyles?.(bookCss(settings))
}

export const highlightDraw = (
  rects: DOMRectList | DOMRect[],
  options: { color?: string } = {},
) => {
  const ns = 'http://www.w3.org/2000/svg'
  const group = document.createElementNS(ns, 'g')
  group.setAttribute('fill', options.color ?? '#c4a35a')
  group.style.opacity = '0.38'
  group.style.mixBlendMode = 'multiply'
  for (const rect of Array.from(rects)) {
    const el = document.createElementNS(ns, 'rect')
    el.setAttribute('x', String(rect.left))
    el.setAttribute('y', String(rect.top))
    el.setAttribute('width', String(rect.width))
    el.setAttribute('height', String(rect.height))
    group.append(el)
  }
  return group
}

export const labelOf = (value: unknown): string => {
  if (typeof value === 'string') return value
  if (Array.isArray(value)) return labelOf(value[0])
  return ''
}
