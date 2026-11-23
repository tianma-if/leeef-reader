export type ReadableNode = {
  localName: string
  getAttribute: (name: string) => string | null
  parentElement: ReadableNode | null
  querySelector?: (selector: string) => ReadableNode | null
}

export type ReadingTarget =
  | { kind: 'footnote'; inline: string; hash: string | null }
  | { kind: 'image'; src: string; alt: string }
  | { kind: 'table' }
  | { kind: 'link'; href: string }

const FOOTNOTE_CLASS = /duokan-footnote|zhangyue-footnote|qqreader-footnote|js_readerFooterNote/
const FOOTNOTE_TYPE = /(?:^|\s)(?:noteref|footnote|doc-noteref|doc-footnote)(?:\s|$)/

const isFootnote = (node: ReadableNode) => {
  const type = `${node.getAttribute('epub:type') ?? ''} ${node.getAttribute('role') ?? ''}`
  return FOOTNOTE_TYPE.test(type) || FOOTNOTE_CLASS.test(node.getAttribute('class') ?? '')
}

const imageSource = (node: ReadableNode) =>
  node.getAttribute('src')
  || node.getAttribute('href')
  || node.getAttribute('xlink:href')
  || ''

/** What a tap in the book should do before it is allowed to turn the page. */
export const classifyReadingTarget = (start: ReadableNode | null): ReadingTarget | null => {
  let image: Extract<ReadingTarget, { kind: 'image' }> | null = null
  let table = false
  let link: Extract<ReadingTarget, { kind: 'link' }> | null = null
  let node = start
  for (let depth = 0; node && depth < 12; depth += 1, node = node.parentElement) {
    if (isFootnote(node)) {
      const href = node.getAttribute('href') ?? ''
      return {
        kind: 'footnote',
        inline: (
          node.getAttribute('data-wr-footernote')
          || node.getAttribute('zy-footnote')
          || node.getAttribute('alt')
          || node.querySelector?.('img')?.getAttribute('alt')
          || ''
        ).trim(),
        hash: href.startsWith('#') ? href : null,
      }
    }
    if (!image && (node.localName === 'img' || node.localName === 'image')) {
      image = { kind: 'image', src: imageSource(node), alt: node.getAttribute('alt') ?? '' }
    }
    if (node.localName === 'table') table = true
    if (!link && node.localName === 'a') {
      const href = node.getAttribute('href')
      if (href) link = { kind: 'link', href }
    }
  }
  if (image?.src) return image
  if (table) return { kind: 'table' }
  return link
}

export const resolveFootnoteText = (
  inline: string,
  hash: string | null,
  lookup: (id: string) => string | null,
) => {
  const direct = inline.replace(/\s+/g, ' ').trim()
  if (direct) return direct.slice(0, 4000)
  if (!hash || hash === '#') return ''
  let id = hash.slice(1)
  try { id = decodeURIComponent(id) } catch { /* keep the raw fragment */ }
  return (lookup(id) ?? '').replace(/\s+/g, ' ').trim().slice(0, 4000)
}
