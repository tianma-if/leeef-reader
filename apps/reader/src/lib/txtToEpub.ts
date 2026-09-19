import { strToU8, zipSync } from 'fflate'

const CHAPTER_RE =
  /^(第[零〇一二三四五六七八九十百千万0-9]+[章节回部卷]|Chapter\s+\d+)(.*)$/u

const INVALID_XML = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u0084\u0086-\u009F\uD800-\uDFFF\uFDD0-\uFDEF\uFFFE\uFFFF]/g

const stripInvalidXml = (value: string) => value.replace(INVALID_XML, '')

const escapeXml = (value: string) =>
  stripInvalidXml(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')

const replacementCount = (text: string) => text.split('\uFFFD').length - 1

const decodeWith = (bytes: Uint8Array, encoding: string) => {
  try {
    return new TextDecoder(encoding).decode(bytes)
  } catch {
    return null
  }
}

const decodeText = (bytes: Uint8Array) => {
  if (bytes.length >= 2 && bytes[0] === 0xff && bytes[1] === 0xfe) {
    return new TextDecoder('utf-16le').decode(bytes.slice(2))
  }
  if (bytes.length >= 2 && bytes[0] === 0xfe && bytes[1] === 0xff) {
    return new TextDecoder('utf-16be').decode(bytes.slice(2))
  }
  if (bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
    return new TextDecoder('utf-8').decode(bytes.slice(3))
  }
  const utf8 = new TextDecoder('utf-8').decode(bytes)
  const utf8Bad = replacementCount(utf8)
  if (utf8Bad === 0) return utf8
  for (const encoding of ['gb18030', 'gbk']) {
    const decoded = decodeWith(bytes, encoding)
    if (decoded && replacementCount(decoded) < utf8Bad) return decoded
  }
  return utf8
}

const splitChapters = (text: string, fallbackTitle: string) => {
  const lines = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n')
  const chapters: { title: string; paragraphs: string[] }[] = []
  let current = { title: fallbackTitle, paragraphs: [] as string[] }

  const flush = () => {
    if (current.paragraphs.some((p) => p.trim())) chapters.push(current)
  }

  for (const raw of lines) {
    const line = raw.trim()
    const heading = line.match(CHAPTER_RE)
    if (heading && line.length < 80) {
      flush()
      current = { title: line, paragraphs: [] }
      continue
    }
    if (line) current.paragraphs.push(line)
  }
  flush()
  if (!chapters.length) {
    const chunks: { title: string; paragraphs: string[] }[] = []
    const lines = text
      .replace(/\r\n/g, '\n')
      .replace(/\r/g, '\n')
      .split('\n')
      .map((line) => line.trim())
      .filter(Boolean)
    const size = 80
    for (let index = 0; index < lines.length; index += size) {
      chunks.push({
        title: `${fallbackTitle} ${chunks.length + 1}`,
        paragraphs: lines.slice(index, index + size),
      })
    }
    return chunks.length ? chunks : [{ title: fallbackTitle, paragraphs: [text] }]
  }
  return chapters
}

const chapterXhtml = (title: string, paragraphs: string[]) => `<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh-CN" lang="zh-CN">
  <head>
    <title>${escapeXml(title)}</title>
    <style>
      body { margin: 0; }
      h1 { font-size: 1.4em; margin: 0 0 1em; }
      p { margin: 0 0 0.8em; text-indent: 2em; line-height: 1.7; }
    </style>
  </head>
  <body>
    <h1>${escapeXml(title)}</h1>
    ${paragraphs.map((p) => `<p>${escapeXml(p)}</p>`).join('\n    ')}
  </body>
</html>
`

export const txtToEpub = (bytes: Uint8Array, filename: string) => {
  const title = filename.replace(/\.[^.]+$/, '') || '未命名'
  const chapters = splitChapters(decodeText(bytes), title)
  const manifestItems = chapters
    .map(
      (_, index) =>
        `<item id="chap${index + 1}" href="text/chap${index + 1}.xhtml" media-type="application/xhtml+xml"/>`,
    )
    .join('\n    ')
  const spineItems = chapters
    .map((_, index) => `<itemref idref="chap${index + 1}"/>`)
    .join('\n    ')
  const navPoints = chapters
    .map(
      (chapter, index) => `    <navPoint id="nav${index + 1}" playOrder="${index + 1}">
      <navLabel><text>${escapeXml(chapter.title)}</text></navLabel>
      <content src="text/chap${index + 1}.xhtml"/>
    </navPoint>`,
    )
    .join('\n')

  const files: Record<string, Uint8Array> = {
    mimetype: strToU8('application/epub+zip'),
    'META-INF/container.xml': strToU8(`<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
`),
    'OEBPS/content.opf': strToU8(`<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>${escapeXml(title)}</dc:title>
    <dc:language>zh-CN</dc:language>
    <dc:identifier id="bookid">leeef-txt-${Date.now()}</dc:identifier>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    ${manifestItems}
  </manifest>
  <spine toc="ncx">
    ${spineItems}
  </spine>
</package>
`),
    'OEBPS/toc.ncx': strToU8(`<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="leeef-txt"/>
  </head>
  <docTitle><text>${escapeXml(title)}</text></docTitle>
  <navMap>
${navPoints}
  </navMap>
</ncx>
`),
  }

  chapters.forEach((chapter, index) => {
    files[`OEBPS/text/chap${index + 1}.xhtml`] = strToU8(
      chapterXhtml(chapter.title, chapter.paragraphs),
    )
  })

  return zipSync(files, { level: 0 })
}

export const isTxtFilename = (name: string) => name.toLowerCase().endsWith('.txt')
