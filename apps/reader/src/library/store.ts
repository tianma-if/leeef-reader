import { unzipSync, strFromU8 } from 'fflate'
import { isTxtFilename, txtToEpub } from '../lib/txtToEpub'

export type LibraryBook = {
  id: string
  title: string
  author: string
  format: string
  fileName: string
  addedAt: number
  lastOpenedAt: number | null
  progress: number
  locator: string | null
}

const DB_NAME = 'leeef-library'
const DB_VERSION = 2

const openDb = () =>
  new Promise<IDBDatabase>((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION)
    request.onupgradeneeded = () => {
      const db = request.result
      for (const name of [...db.objectStoreNames]) db.deleteObjectStore(name)
      db.createObjectStore('meta', { keyPath: 'id' })
      db.createObjectStore('files')
    }
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })

const txDone = (tx: IDBTransaction) =>
  new Promise<void>((resolve, reject) => {
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error)
    tx.onabort = () => reject(tx.error)
  })

const localized = (value: unknown): string => {
  if (typeof value === 'string') return value.trim()
  if (Array.isArray(value)) return localized(value[0])
  if (value && typeof value === 'object') {
    const record = value as Record<string, unknown>
    return localized(record['zh'] ?? record['zh-CN'] ?? Object.values(record)[0])
  }
  return ''
}

const formatOf = (name: string) => {
  const ext = name.split('.').pop()?.toLowerCase() ?? ''
  return ext || 'epub'
}

const titleFromEpub = (bytes: Uint8Array) => {
  try {
    const entries = unzipSync(bytes)
    const container = entries['META-INF/container.xml']
    if (!container) return { title: '', author: '' }
    const xml = strFromU8(container)
    const opfPath = xml.match(/full-path="([^"]+)"/)?.[1]
    if (!opfPath || !entries[opfPath]) return { title: '', author: '' }
    const opf = strFromU8(entries[opfPath])
    const title = opf.match(/<dc:title[^>]*>([^<]+)<\/dc:title>/i)?.[1]
    const author = opf.match(/<dc:creator[^>]*>([^<]+)<\/dc:creator>/i)?.[1]
    return { title: title?.trim() ?? '', author: author?.trim() ?? '' }
  } catch {
    return { title: '', author: '' }
  }
}

const displayName = (fileName: string) => fileName.replace(/\.[^.]+$/, '')

export const listBooks = async (): Promise<LibraryBook[]> => {
  const db = await openDb()
  const books = await new Promise<LibraryBook[]>((resolve, reject) => {
    const request = db.transaction('meta').objectStore('meta').getAll()
    request.onsuccess = () => resolve((request.result as LibraryBook[]) ?? [])
    request.onerror = () => reject(request.error)
  })
  db.close()
  return books.sort((a, b) => (b.lastOpenedAt ?? b.addedAt) - (a.lastOpenedAt ?? a.addedAt))
}

export const getBookFile = async (id: string): Promise<Uint8Array | null> => {
  const db = await openDb()
  const bytes = await new Promise<Uint8Array | null>((resolve, reject) => {
    const request = db.transaction('files').objectStore('files').get(id)
    request.onsuccess = () => {
      const value = request.result
      if (!value) {
        resolve(null)
        return
      }
      resolve(value instanceof Uint8Array ? value : new Uint8Array(value as ArrayBuffer))
    }
    request.onerror = () => reject(request.error)
  })
  db.close()
  return bytes
}

export const saveProgress = async (
  id: string,
  progress: number,
  locator: string | null,
) => {
  const db = await openDb()
  const tx = db.transaction('meta', 'readwrite')
  const store = tx.objectStore('meta')
  const current = await new Promise<LibraryBook | undefined>((resolve, reject) => {
    const request = store.get(id)
    request.onsuccess = () => resolve(request.result as LibraryBook | undefined)
    request.onerror = () => reject(request.error)
  })
  if (current) {
    store.put({
      ...current,
      progress,
      locator,
      lastOpenedAt: Date.now(),
    })
  }
  await txDone(tx)
  db.close()
}

export const removeBook = async (id: string) => {
  const db = await openDb()
  const tx = db.transaction(['meta', 'files'], 'readwrite')
  tx.objectStore('meta').delete(id)
  tx.objectStore('files').delete(id)
  await txDone(tx)
  db.close()
}

export const importFiles = async (files: File[]): Promise<LibraryBook[]> => {
  const imported: LibraryBook[] = []
  for (const file of files) {
    const source = new Uint8Array(await file.arrayBuffer())
    const asEpub = isTxtFilename(file.name)
    const bytes = asEpub ? txtToEpub(source, file.name) : source
    const meta = asEpub ? { title: '', author: '' } : titleFromEpub(bytes)
    const title = meta.title || displayName(file.name)
    const book: LibraryBook = {
      id: crypto.randomUUID(),
      title,
      author: meta.author || '',
      format: asEpub ? 'epub' : formatOf(file.name),
      fileName: asEpub ? file.name.replace(/\.txt$/i, '.epub') : file.name,
      addedAt: Date.now(),
      lastOpenedAt: null,
      progress: 0,
      locator: null,
    }
    const db = await openDb()
    const tx = db.transaction(['meta', 'files'], 'readwrite')
    tx.objectStore('meta').put(book)
    tx.objectStore('files').put(bytes, book.id)
    await txDone(tx)
    db.close()
    imported.push(book)
  }
  return imported
}
