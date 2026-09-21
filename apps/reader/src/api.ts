import { convertFileSrc, invoke } from '@tauri-apps/api/core'

export type Book = {
  id: string
  sha256: string
  title: string
  author?: string | null
  description?: string | null
  mediaType: string
  filePath?: string | null
  coverPath?: string | null
  rating?: number | null
  isAvailableLocally: boolean
  createdAt: string
  updatedAt: string
  progress: number
  locator?: string | null
  chapterTitle?: string | null
  tags: string[]
  shelfIds: string[]
}

export type Excerpt = {
  id: string
  bookId: string
  locator: string
  quote: string
  note?: string | null
  color: string
  createdAt: string
  bookTitle?: string | null
}

export type Bookmark = {
  id: string
  bookId: string
  locator: string
  title?: string | null
  note?: string | null
  createdAt: string
}

export type Tag = { id: string; name: string; color: number }
export type Shelf = { id: string; parentId?: string | null; name: string; sortOrder: number }
export type Session = {
  id: string
  bookId: string
  startedAt: string
  endedAt: string
  durationSeconds: number
}

export type Settings = {
  theme?: 'paper' | 'night' | 'sepia'
  fontSize?: number
  lineHeight?: number
  fontFamily?: string
  flow?: 'paginated' | 'scrolled'
  columns?: 1 | 2
  ttsRate?: number
  aiEndpoint?: string
  aiKey?: string
  aiModel?: string
  opdsCatalogs?: { name: string; url: string }[]
  syncBackend?: 's3' | 'webdav' | ''
  syncEndpoint?: string
  chinese?: 'original' | 'simplified' | 'traditional'
  edgeEverEnabled?: boolean
  edgeEverEndpoint?: string
  edgeEverToken?: string
  edgeEverNotebookId?: string
}

export type EdgeEverSyncResult = {
  configured: boolean
  synced: number
  skipped: number
  failed: number
  errors: string[]
}

const asBytes = (raw: ArrayBuffer | Uint8Array | number[]): Uint8Array<ArrayBuffer> =>
  raw instanceof ArrayBuffer ? new Uint8Array(raw) : new Uint8Array(raw)

const toB64 = (bytes: Uint8Array) => {
  let binary = ''
  const chunk = 0x8000
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode.apply(null, Array.from(bytes.subarray(i, i + chunk)))
  }
  return btoa(binary)
}

export const api = {
  listBooks: () => invoke<Book[]>('list_books'),
  importBook: (input: {
    name: string
    data: Uint8Array
    title: string
    author?: string
    mediaType: string
    cover?: Uint8Array
  }) =>
    invoke<Book>('import_book', {
      payload: {
        name: input.name,
        data: toB64(input.data),
        title: input.title,
        author: input.author ?? null,
        mediaType: input.mediaType,
        cover: input.cover ? toB64(input.cover) : null,
      },
    }),
  deleteBook: (id: string) => invoke('delete_book', { id }),
  updateBook: (id: string, title?: string, author?: string, rating?: number) =>
    invoke('update_book', { id, title: title ?? null, author: author ?? null, rating: rating ?? null }),
  bookBytes: async (id: string) =>
    asBytes(await invoke<ArrayBuffer | number[]>('book_bytes', { id })),
  bookCover: async (id: string) =>
    asBytes(await invoke<ArrayBuffer | number[]>('book_cover', { id })),
  bookFileUrl: (filePath: string) => convertFileSrc(filePath),
  saveProgress: (
    bookId: string,
    locator: string,
    progress: number,
    chapterTitle?: string,
  ) => invoke('save_progress', { bookId, locator, progress, chapterTitle: chapterTitle ?? null }),
  listExcerpts: (bookId?: string) =>
    invoke<Excerpt[]>('list_excerpts', { bookId: bookId ?? null }),
  createExcerpt: (input: {
    bookId: string
    locator: string
    quote: string
    note?: string
    color: string
  }) =>
    invoke('create_excerpt', {
      bookId: input.bookId,
      locator: input.locator,
      quote: input.quote,
      note: input.note ?? null,
      color: input.color,
    }),
  updateExcerpt: (input: {
    id: string
    quote: string
    note?: string
    color: string
  }) => invoke('update_excerpt', {
    id: input.id,
    quote: input.quote,
    note: input.note ?? null,
    color: input.color,
  }),
  deleteExcerpt: (id: string) => invoke('delete_excerpt', { id }),
  listBookmarks: (bookId: string) => invoke<Bookmark[]>('list_bookmarks', { bookId }),
  addBookmark: (bookId: string, locator: string, title?: string) =>
    invoke('add_bookmark', { bookId, locator, title: title ?? null }),
  deleteBookmark: (id: string) => invoke('delete_bookmark', { id }),
  listShelves: () => invoke<Shelf[]>('list_shelves'),
  createShelf: (name: string, parentId?: string) =>
    invoke('create_shelf', { name, parentId: parentId ?? null }),
  addBookToShelf: (shelfId: string, bookId: string) =>
    invoke('add_book_to_shelf', { shelfId, bookId }),
  removeBookFromShelf: (shelfId: string, bookId: string) =>
    invoke('remove_book_from_shelf', { shelfId, bookId }),
  listTags: () => invoke<Tag[]>('list_tags'),
  createTag: (name: string, color: number) => invoke('create_tag', { name, color }),
  setBookTag: (bookId: string, tagId: string, on: boolean) =>
    invoke('set_book_tag', { bookId, tagId, on }),
  recordSession: (bookId: string, seconds: number) =>
    invoke('record_session', { bookId, seconds }),
  listSessions: () => invoke<Session[]>('list_sessions'),
  getSettings: () => invoke<Settings>('get_settings'),
  saveSettings: (value: Settings) => invoke('save_settings', { value }),
  edgeEverTest: () => invoke<{ ok: boolean; message: string }>('edgeever_test'),
  edgeEverNotebooks: () => invoke<{ id: string; name: string }[]>('edgeever_notebooks'),
  edgeEverSyncAll: () => invoke<EdgeEverSyncResult>('edgeever_sync_all'),
  mcpDatabasePath: () => invoke<string>('mcp_database_path'),
  mcpStart: () =>
    invoke<{ running: boolean; endpoint?: string; token?: string; databasePath: string }>(
      'mcp_start',
    ),
  mcpStop: () =>
    invoke<{ running: boolean; endpoint?: string; token?: string; databasePath: string }>(
      'mcp_stop',
    ),
  mcpStatus: () =>
    invoke<{ running: boolean; endpoint?: string; token?: string; databasePath: string }>(
      'mcp_status',
    ),
  pairingCode: () => invoke<string>('pairing_code'),
}

export const isAndroid = () => /Android/i.test(navigator.userAgent)
export const isMobile = () => /Android|iPhone|iPad|iPod/i.test(navigator.userAgent)
