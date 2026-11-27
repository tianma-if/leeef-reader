import { Channel, convertFileSrc, invoke } from '@tauri-apps/api/core'

type AppInfo = {
  version: string
  platform: string
  osVersion: string | null
  arch: string
  debug: boolean
  tauriVersion: string
  webviewVersion: string | null
}

export type McpStatus = {
  running: boolean
  endpoint: string | null
  token: string | null
  databasePath: string
  error: string | null
}

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

export type ReadingDestination = { book: Book; previewLocator: string | null }

export type Excerpt = {
  id: string
  bookId: string
  locator: string
  quote: string
  note?: string | null
  color: string
  createdAt: string
  bookTitle?: string | null
  chapter?: ExcerptChapter | null
}

export type ExcerptChapter = { key: string; title: string }

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
  /** Mobile paginated turn. `push` is the paginator strip; `slide` is the captured sheet. */
  pageTurn?: 'push' | 'slide'
  columns?: 1 | 2
  ttsRate?: number
  aiEndpoint?: string
  aiKey?: string
  aiModel?: string
  syncBackend?: 's3' | 'webdav' | ''
  syncEndpoint?: string
  syncUsername?: string
  syncPassword?: string
  syncBucket?: string
  syncRegion?: string
  syncAccessKey?: string
  syncSecretKey?: string
  syncPrefix?: string
  syncLibrary?: boolean
  autoSync?: boolean
  chinese?: 'original' | 'simplified' | 'traditional'
  edgeEverEnabled?: boolean
  edgeEverEndpoint?: string
  edgeEverToken?: string
  edgeEverNotebookId?: string
  edgeEverNotebookLabel?: EdgeEverNotebook
}

export type EdgeEverNotebook = { id: string; name: string }

export type EdgeEverStatus = {
  enabled: boolean
  configured: boolean
  notebookSelected: boolean
  notebookName: string | null
  targetKey: string | null
  lastAttempt: { finishedAt: number; succeeded: boolean } | null
}

export type EdgeEverSyncResult = {
  configured: boolean
  synced: number
  skipped: number
  failed: number
  errors: string[]
}

export type SettingsSyncStatus = {
  paired: boolean
  pairedDevices: { id: string; name: string | null }[]
  configured: boolean
  autoSync: boolean
  running: boolean
  lastSuccessAt?: number
  lastError?: string
  appliedValues: number
  lastAttemptAt?: number
  libraryEnabled: boolean
  pendingRecords?: number
  progress: { phase: string; completed: number; total: number; currentItem?: string }
}

export type LibraryRevision = { modifiedAt: number; deviceId: string }
export type LibraryHistoryRecord = LibraryRevision & {
  table: 'excerpts' | 'reading_progresses'
  key: string
  deleted: boolean
  data: { quote?: string; note?: string | null; locator?: string; progress?: number; chapter_title?: string | null; is_deleted?: number }
}
export type LibraryHistoryEntry = {
  id: number
  bookTitle: string
  restorable: boolean
  record: LibraryHistoryRecord
  current: LibraryHistoryRecord | null
}

export type BackupPreview = { books: number; excerpts: number; bookmarks: number; bytes: number; matchingBooks: number }

export type PairingOffer = {
  sessionId: string
  code: string
  expiresAt: number
  qr: { width: number; modules: string } | null
}

export type PairingPeer = {
  name: string
  sessionId: string
  hostPublicKey: string
  addresses: string[]
  port: number
  expiresAt: number
}

export type PairingHostStatus = {
  active: boolean
  completed: boolean
  pending: { id: string; deviceName: string; verification: string } | null
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
  takeReadingLink: () => invoke<ReadingDestination | null>('take_reading_link'),
  listBooks: () => invoke<Book[]>('list_books'),
  importBook: (input: {
    name: string
    data: Uint8Array
    title?: string
    author?: string
    mediaType: string
    cover?: Uint8Array
  }) =>
    invoke<Book>('import_book', {
      payload: {
        name: input.name,
        data: toB64(input.data),
        title: input.title ?? null,
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
    chapter?: ExcerptChapter
  }) =>
    invoke<string>('create_excerpt', {
      bookId: input.bookId,
      locator: input.locator,
      quote: input.quote,
      note: input.note ?? null,
      color: input.color,
      chapter: input.chapter ?? null,
    }),
  cacheExcerptChapters: (bookId: string, chapters: [string, ExcerptChapter][]) =>
    invoke<void>('cache_excerpt_chapters', { bookId, chapters }),
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
  getAppInfo: () => invoke<AppInfo>('get_app_info'),
  getSettings: () => invoke<Settings>('get_settings'),
  saveSettings: (value: Settings) => invoke('save_settings', { value }),
  edgeEverTest: (draft?: Settings) => invoke<{ ok: boolean; message: string }>('edgeever_test', { draft }),
  edgeEverNotebooks: (draft?: Settings) => invoke<EdgeEverNotebook[]>('edgeever_notebooks', { draft }),
  edgeEverStatus: () => invoke<EdgeEverStatus>('edgeever_status'),
  edgeEverSyncAll: () => invoke<EdgeEverSyncResult>('edgeever_sync_all'),
  mcpStart: () => invoke<McpStatus>('mcp_start'),
  mcpStop: () => invoke<McpStatus>('mcp_stop'),
  mcpStatus: () => invoke<McpStatus>('mcp_status'),
  pairingStart: () => invoke<PairingOffer>('pairing_start'),
  pairingJoin: (code: string, replaceExisting = false) =>
    invoke<SettingsSyncStatus>('pairing_join', { code, replaceExisting }),
  pairingNearby: () => invoke<PairingPeer[]>('pairing_nearby'),
  pairingJoinPeer: (peer: PairingPeer, replaceExisting: boolean, onVerification: (code: string) => void) => {
    const verification = new Channel<string>(onVerification)
    return invoke<SettingsSyncStatus>('pairing_join_peer', { peer, replaceExisting, verification })
  },
  pairingScanQr: (replaceExisting: boolean) =>
    invoke<SettingsSyncStatus | null>('pairing_scan_qr', { replaceExisting }),
  pairingStatus: (sessionId: string) => invoke<PairingHostStatus>('pairing_status', { sessionId }),
  pairingDecide: (sessionId: string, approvalId: string, approve: boolean) =>
    invoke<void>('pairing_decide', { sessionId, approvalId, approve }),
  pairingStop: (sessionId: string) => invoke<void>('pairing_stop', { sessionId }),
  pairingCancelJoin: () => invoke<void>('pairing_cancel_join'),
  libraryHistory: (beforeId: number | null = null, kind: 'excerpts' | 'reading_progresses' | null = null) => invoke<LibraryHistoryEntry[]>('library_history', { beforeId, kind }),
  libraryHistoryRestore: (id: number, expected: LibraryRevision | null) => invoke<void>('library_history_restore', { id, expected }),
  settingsSyncStatus: () => invoke<SettingsSyncStatus>('settings_sync_status'),
  settingsSyncNow: () => invoke<SettingsSyncStatus>('settings_sync_now'),
  settingsRecoveryExport: (password: string) =>
    invoke<string>('settings_recovery_export', { password }),
  settingsRecoveryImport: (packageText: string, password: string, replaceExisting: boolean) =>
    invoke<SettingsSyncStatus>('settings_recovery_import', {
      package: packageText,
      password,
      replaceExisting,
    }),
  libraryBackupExport: (password: string) => invoke<string>('library_backup_export', { password }),
  libraryBackupPreview: (packageText: string, password: string) =>
    invoke<BackupPreview>('library_backup_preview', { package: packageText, password }),
  libraryBackupRestore: (packageText: string, password: string, preferBackup: boolean) =>
    invoke<number>('library_backup_restore', { package: packageText, password, preferBackup }),
  saveTextFile: (filename: string, content: string) =>
    invoke<{ saved: boolean }>('plugin:native-bridge|save_text_file', {
      payload: { filename, content },
    }),
}

export const isAndroid = () => /Android/i.test(navigator.userAgent)
export const isMobile = () => /Android|iPhone|iPad|iPod/i.test(navigator.userAgent)
