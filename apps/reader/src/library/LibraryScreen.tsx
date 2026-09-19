import { invoke } from '@tauri-apps/api/core'
import { useEffect, useState } from 'react'
import {
  importFiles,
  listBooks,
  removeBook,
  type LibraryBook,
} from './store'

const isAndroid = () => /Android/i.test(navigator.userAgent)

const decodeBase64 = (data: string) => {
  const binary = atob(data)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i)
  return bytes
}

type Props = {
  onOpen: (book: LibraryBook) => void
}

const ACCEPT = '.epub,.txt,.mobi,.azw3,.fb2,application/epub+zip,text/plain'

export function LibraryScreen({ onOpen }: Props) {
  const [books, setBooks] = useState<LibraryBook[]>([])
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const reload = async () => {
    setBooks(await listBooks())
  }

  useEffect(() => {
    void reload().catch((cause) => setError(String(cause)))
  }, [])

  const importPicked = async (files: File[]) => {
    if (!files.length) {
      setBusy(false)
      return
    }
    setBusy(true)
    setError(null)
    try {
      await importFiles(files)
      await reload()
    } catch (cause) {
      setError(String(cause))
    } finally {
      setBusy(false)
    }
  }

  const onPick = (fileList: FileList | null) => {
    if (fileList?.length) void importPicked([...fileList])
  }

  const onAndroidImport = async () => {
    setBusy(true)
    setError(null)
    try {
      const picked = await invoke<{ name: string; data: string }[]>(
        'plugin:native-bridge|pick_books',
      )
      const files = (picked ?? []).map(
        (item) => new File([new Blob([decodeBase64(item.data)])], item.name),
      )
      await importPicked(files)
    } catch (cause) {
      setBusy(false)
      setError(String(cause))
    }
  }

  const onDelete = async (book: LibraryBook) => {
    if (!window.confirm(`从书架删除「${book.title}」？`)) return
    await removeBook(book.id)
    await reload()
  }

  return (
    <main className="shelf">
      <header className="shelf-bar">
        <h1>书架</h1>
        {isAndroid() ? (
          <button
            type="button"
            className="shelf-import"
            disabled={busy}
            onClick={() => void onAndroidImport()}
          >
            {busy ? '导入中…' : '导入'}
          </button>
        ) : (
          <label className="shelf-import">
            {busy ? '导入中…' : '导入'}
            <input
              type="file"
              accept={ACCEPT}
              multiple
              disabled={busy}
              onChange={(event) => {
                const files = event.target.files
                event.target.value = ''
                onPick(files)
              }}
            />
          </label>
        )}
      </header>
      {error ? <p className="reader-error">{error}</p> : null}
      {books.length === 0 ? (
        <p className="shelf-empty">还没有书。点右上角导入 EPUB / TXT / MOBI / AZW3 / FB2。</p>
      ) : (
        <ul className="shelf-grid">
          {books.map((book) => (
            <li key={book.id}>
              <button
                type="button"
                className="shelf-card"
                onClick={() => onOpen(book)}
                onContextMenu={(event) => {
                  event.preventDefault()
                  void onDelete(book)
                }}
              >
                <div className="shelf-cover" aria-hidden="true">
                  <span>{book.title.slice(0, 1)}</span>
                </div>
                <strong>{book.title}</strong>
                <em>
                  {book.progress > 0.001
                    ? `${Math.round(book.progress * 100)}%`
                    : '未读'}
                </em>
              </button>
            </li>
          ))}
        </ul>
      )}
    </main>
  )
}
