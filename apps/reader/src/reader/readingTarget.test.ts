import { expect, it } from 'vitest'
import { classifyReadingTarget, resolveFootnoteText, type ReadableNode } from './readingTarget'

const node = (
  localName: string,
  attributes: Record<string, string> = {},
  parent: ReadableNode | null = null,
): ReadableNode => ({
  localName,
  parentElement: parent,
  getAttribute: (name) => attributes[name] ?? null,
})

it('opens a footnote instead of following the note link', () => {
  const anchor = node('a', { 'href': '#n1', 'epub:type': 'noteref' })
  expect(classifyReadingTarget(node('span', {}, anchor))).toEqual({
    kind: 'footnote',
    inline: '',
    hash: '#n1',
  })
  expect(resolveFootnoteText('', '#n1', (id) => id === 'n1' ? '注：原文如此。' : null)).toBe('注：原文如此。')
})

it('reads vendor footnote text stored on the anchor', () => {
  const anchor = node('a', { class: 'duokan-footnote', 'zy-footnote': '多看注释' })
  expect(classifyReadingTarget(anchor)).toMatchObject({ kind: 'footnote', inline: '多看注释' })
})

it('prefers an image over the link or page turn around it', () => {
  const link = node('a', { href: 'full.jpg' })
  const image = node('img', { src: 'full.jpg', alt: '插图' }, link)
  expect(classifyReadingTarget(image)).toEqual({ kind: 'image', src: 'full.jpg', alt: '插图' })
})

it('keeps ordinary links on the navigation path', () => {
  expect(classifyReadingTarget(node('a', { href: 'chapter2.xhtml' }))).toEqual({
    kind: 'link',
    href: 'chapter2.xhtml',
  })
})

it('notices a table under the tap', () => {
  const table = node('table')
  expect(classifyReadingTarget(node('td', {}, table))).toEqual({ kind: 'table' })
})
