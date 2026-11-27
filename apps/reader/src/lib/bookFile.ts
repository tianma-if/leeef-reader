import { isTxtFilename, txtToEpub } from './txtToEpub'

export const prepareBookFile = (file: File, source: Uint8Array) => {
  if (isTxtFilename(file.name)) {
    return {
      name: file.name.replace(/\.txt$/i, '.epub'),
      bytes: txtToEpub(source, file.name),
      title: file.name.replace(/\.[^.]+$/, ''),
      mediaType: 'application/epub+zip',
    }
  }
  const ext = file.name.split('.').pop()?.toLowerCase() ?? 'bin'
  const mediaType =
    ext === 'pdf'
      ? 'application/pdf'
      : ext === 'epub'
        ? 'application/epub+zip'
        : `application/${ext}`
  const title = ext === 'epub' ? undefined : file.name.replace(/\.[^.]+$/, '')
  return { name: file.name, bytes: source, title, mediaType }
}
