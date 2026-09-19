import { invoke } from '@tauri-apps/api/core'
import { useEffect, useMemo, useState } from 'react'
import { api, isAndroid, type Book, type Tag } from '../api'
import { prepareBookFile } from '../lib/bookFile'

type Props = {
  onOpen: (book: Book) => void
}

const ACCEPT = '.epub,.txt,.mobi,.azw3,.fb2,.pdf,application/epub+zip,text/plain,application/pdf'

type SortKey = 'updated' | 'title' | 'author' | 'progress' | 'created'
type FilterKey = 'all' | 'unread' | 'reading' | 'done'

const decodeBase64 = (data: string) => {
  const binary = atob(data)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i)
  return bytes
}

export function LibraryScreen({ onOpen }: Props) {
  const [books, setBooks] = useState<Book[]>([])
  const [tags, setTags] = useState<Tag[]>([])
  const [query, setQuery] = useState('')
  const [sort, setSort] = useState<SortKey>('updated')
  const [filter, setFilter] = useState<FilterKey>('all')
  const [tag, setTag] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [editing, setEditing] = useState<Book | null>(null)

  const reload = async () => {
    const [nextBooks, nextTags] = await Promise.all([api.listBooks(), api.listTags()])
    setBooks(nextBooks)
    setTags(nextTags)
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
      for (const file of files) {
        const source = new Uint8Array(await file.arrayBuffer())
        const prepared = prepareBookFile(file, source)
        await api.importBook({
          name: prepared.name,
          data: prepared.bytes,
          title: prepared.title,
          author: prepared.author,
          mediaType: prepared.mediaType,
          cover: prepared.cover,
        })
      }
      await reload()
    } catch (cause) {
      setError(String(cause))
    } finally {
      setBusy(false)
    }
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

  const visible = useMemo(() => {
    let next = books.filter((book) => {
      const hay = `${book.title} ${book.author ?? ''}`.toLowerCase()
      if (query && !hay.includes(query.toLowerCase())) return false
      if (tag && !book.tags.includes(tag)) return false
      if (filter === 'unread') return book.progress < 0.01
      if (filter === 'reading') return book.progress >= 0.01 && book.progress < 0.999
      if (filter === 'done') return book.progress >= 0.999
      return true
    })
    next = [...next].sort((a, b) => {
      if (sort === 'title') return a.title.localeCompare(b.title, 'zh')
      if (sort === 'author') return (a.author ?? '').localeCompare(b.author ?? '', 'zh')
      if (sort === 'progress') return b.progress - a.progress
      if (sort === 'created') return b.createdAt.localeCompare(a.createdAt)
      return 0
    })
    return next
  }, [books, query, sort, filter, tag])

  return (
    <main className="page">
      <header className="page-bar">
        <h1>书架</h1>
        {isAndroid() ? (
          <button type="button" className="btn" disabled={busy} onClick={() => void onAndroidImport()}>
            {busy ? '导入中…' : '导入'}
          </button>
        ) : (
          <label className="btn">
            {busy ? '导入中…' : '导入'}
            <input
              hidden
              type="file"
              accept={ACCEPT}
              multiple
              disabled={busy}
              onChange={(event) => {
                const files = event.target.files
                event.target.value = ''
                if (files) void importPicked([...files])
              }}
            />
          </label>
        )}
      </header>
      <div className="toolbar">
        <input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="搜索书名或作者"
        />
        <select value={filter} onChange={(event) => setFilter(event.target.value as FilterKey)}>
          <option value="all">全部</option>
          <option value="unread">未开始</option>
          <option value="reading">阅读中</option>
          <option value="done">已读完</option>
        </select>
        <select value={sort} onChange={(event) => setSort(event.target.value as SortKey)}>
          <option value="updated">最近阅读</option>
          <option value="title">标题</option>
          <option value="author">作者</option>
          <option value="progress">进度</option>
          <option value="created">导入时间</option>
        </select>
        <select value={tag} onChange={(event) => setTag(event.target.value)}>
          <option value="">全部标签</option>
          {tags.map((item) => (
            <option key={item.id} value={item.name}>
              {item.name}
            </option>
          ))}
        </select>
      </div>
      {error ? <p className="reader-error">{error}</p> : null}
      {visible.length === 0 ? (
        <p className="empty">还没有书。导入 EPUB / TXT / MOBI / AZW3 / FB2 / PDF。</p>
      ) : (
        <ul className="shelf-grid">
          {visible.map((book) => (
            <li key={book.id}>
              <button
                type="button"
                className="shelf-card"
                onClick={() => onOpen(book)}
                onContextMenu={(event) => {
                  event.preventDefault()
                  setEditing(book)
                }}
              >
                <div className="shelf-cover">
                  <span>{book.title.slice(0, 1)}</span>
                </div>
                <strong>{book.title}</strong>
                <em>
                  {book.author ? `${book.author} · ` : ''}
                  {book.progress > 0.001 ? `${Math.round(book.progress * 100)}%` : '未读'}
                </em>
              </button>
            </li>
          ))}
        </ul>
      )}
      {editing ? (
        <div className="modal" onClick={() => setEditing(null)}>
          <form
            className="modal-card"
            onClick={(event) => event.stopPropagation()}
            onSubmit={(event) => {
              event.preventDefault()
              const data = new FormData(event.currentTarget)
              void api
                .updateBook(
                  editing.id,
                  String(data.get('title') ?? editing.title),
                  String(data.get('author') ?? ''),
                )
                .then(reload)
                .then(() => setEditing(null))
            }}
          >
            <h2>书籍详情</h2>
            <label>
              标题
              <input name="title" defaultValue={editing.title} />
            </label>
            <label>
              作者
              <input name="author" defaultValue={editing.author ?? ''} />
            </label>
            <p className="hint">长按/右键打开详情。删除会进回收标记，同步后其他设备也会看到。</p>
            <div className="row">
              <button type="submit" className="btn">
                保存
              </button>
              <button
                type="button"
                className="btn danger"
                onClick={() => {
                  if (window.confirm(`删除「${editing.title}」？`)) {
                    void api.deleteBook(editing.id).then(reload).then(() => setEditing(null))
                  }
                }}
              >
                删除
              </button>
            </div>
          </form>
        </div>
      ) : null}
    </main>
  )
}
