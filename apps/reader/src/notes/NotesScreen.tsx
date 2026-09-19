import { useEffect, useState } from 'react'
import { api, type Excerpt } from '../api'

type Props = { onOpenBook: (bookId: string) => void }

export function NotesScreen({ onOpenBook }: Props) {
  const [items, setItems] = useState<Excerpt[]>([])
  const [query, setQuery] = useState('')

  useEffect(() => {
    void api.listExcerpts().then(setItems)
  }, [])

  const visible = items.filter((item) =>
    `${item.quote} ${item.note ?? ''} ${item.bookTitle ?? ''}`
      .toLowerCase()
      .includes(query.toLowerCase()),
  )

  return (
    <main className="page">
      <header className="page-bar">
        <h1>笔记</h1>
      </header>
      <input
        className="search"
        value={query}
        onChange={(event) => setQuery(event.target.value)}
        placeholder="搜索书摘和笔记"
      />
      {visible.length === 0 ? (
        <p className="empty">还没有书摘。阅读时选中文字即可添加。</p>
      ) : (
        <ul className="note-list">
          {visible.map((item) => (
            <li key={item.id}>
              <button type="button" onClick={() => onOpenBook(item.bookId)}>
                <strong>{item.bookTitle}</strong>
                <p>{item.quote}</p>
                {item.note ? <em>{item.note}</em> : null}
              </button>
              <button
                type="button"
                className="text-btn"
                onClick={() =>
                  void api.deleteExcerpt(item.id).then(() => api.listExcerpts().then(setItems))
                }
              >
                删除
              </button>
            </li>
          ))}
        </ul>
      )}
    </main>
  )
}
