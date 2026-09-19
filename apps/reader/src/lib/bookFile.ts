import { unzipSync, strFromU8 } from 'fflate'
import { isTxtFilename, txtToEpub } from './txtToEpub'

export const prepareBookFile = (file: File, source: Uint8Array) => {
  if (isTxtFilename(file.name)) {
    const bytes = txtToEpub(source, file.name)
    return {
      name: file.name.replace(/\.txt$/i, '.epub'),
      bytes,
      title: file.name.replace(/\.[^.]+$/, ''),
      author: undefined as string | undefined,
      mediaType: 'application/epub+zip',
      cover: undefined as Uint8Array | undefined,
    }
  }
  let title = file.name.replace(/\.[^.]+$/, '')
  let author: string | undefined
  let cover: Uint8Array | undefined
  if (file.name.toLowerCase().endsWith('.epub')) {
    try {
      const entries = unzipSync(source)
      const container = entries['META-INF/container.xml']
      if (container) {
        const opfPath = strFromU8(container).match(/full-path="([^"]+)"/)?.[1]
        if (opfPath && entries[opfPath]) {
          const opf = strFromU8(entries[opfPath])
          title = opf.match(/<dc:title[^>]*>([^<]+)<\/dc:title>/i)?.[1]?.trim() || title
          author = opf.match(/<dc:creator[^>]*>([^<]+)<\/dc:creator>/i)?.[1]?.trim()
          const href = opf.match(/<item[^>]+properties="[^"]*cover-image[^"]*"[^>]+href="([^"]+)"/i)?.[1]
            ?? opf.match(/<item[^>]+id="cover"[^>]+href="([^"]+)"/i)?.[1]
          if (href) {
            const dir = opfPath.split('/').slice(0, -1).join('/')
            const path = (dir ? `${dir}/` : '') + href
            cover = entries[path]
          }
        }
      }
    } catch {
      /* keep filename */
    }
  }
  const ext = file.name.split('.').pop()?.toLowerCase() ?? 'bin'
  const mediaType =
    ext === 'pdf'
      ? 'application/pdf'
      : ext === 'epub'
        ? 'application/epub+zip'
        : `application/${ext}`
  return { name: file.name, bytes: source, title, author, mediaType, cover }
}
