import { useEffect, useMemo, useState } from 'react'
import { api, type Book, type Session } from '../api'

export function StatsScreen() {
  const [sessions, setSessions] = useState<Session[]>([])
  const [books, setBooks] = useState<Book[]>([])

  useEffect(() => {
    void Promise.all([api.listSessions(), api.listBooks()]).then(([nextSessions, nextBooks]) => {
      setSessions(nextSessions)
      setBooks(nextBooks)
    })
  }, [])

  const totalSeconds = sessions.reduce((sum, item) => sum + item.durationSeconds, 0)
  const days = new Set(sessions.map((item) => item.startedAt.slice(0, 10))).size
  const notesReady = books.filter((book) => book.progress >= 0.999).length

  const byBook = useMemo(() => {
    const map = new Map<string, number>()
    for (const session of sessions) {
      map.set(session.bookId, (map.get(session.bookId) ?? 0) + session.durationSeconds)
    }
    return [...map.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([id, seconds]) => ({
        title: books.find((book) => book.id === id)?.title ?? id,
        seconds,
      }))
  }, [sessions, books])

  return (
    <main className="page">
      <header className="page-bar">
        <h1>统计</h1>
      </header>
      <section className="stat-grid">
        <article>
          <strong>{Math.round(totalSeconds / 60)}</strong>
          <span>阅读分钟</span>
        </article>
        <article>
          <strong>{days}</strong>
          <span>阅读天数</span>
        </article>
        <article>
          <strong>{books.length}</strong>
          <span>书籍</span>
        </article>
        <article>
          <strong>{notesReady}</strong>
          <span>已读完</span>
        </article>
      </section>
      <h2>阅读最多</h2>
      <ul className="plain">
        {byBook.map((item) => (
          <li key={item.title}>
            {item.title} · {Math.round(item.seconds / 60)} 分钟
          </li>
        ))}
      </ul>
    </main>
  )
}
