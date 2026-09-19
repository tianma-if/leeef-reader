import { useEffect, useMemo, useState } from 'react'
import { api, type Book, type Session } from '../api'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

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

  const cards = [
    { label: '阅读分钟', value: Math.round(totalSeconds / 60) },
    { label: '阅读天数', value: days },
    { label: '书籍', value: books.length },
    { label: '已读完', value: notesReady },
  ]

  return (
    <main className="px-4 pt-4 pb-6">
      <h1 className="font-heading mb-4 text-2xl">统计</h1>
      <div className="mb-6 grid grid-cols-2 gap-3">
        {cards.map((card) => (
          <Card key={card.label}>
            <CardHeader>
              <CardTitle className="text-muted-foreground text-sm font-normal">
                {card.label}
              </CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-3xl font-medium">{card.value}</p>
            </CardContent>
          </Card>
        ))}
      </div>
      <h2 className="mb-3 text-lg">阅读最多</h2>
      <ul className="space-y-2 text-sm">
        {byBook.map((item) => (
          <li key={item.title}>
            {item.title} · {Math.round(item.seconds / 60)} 分钟
          </li>
        ))}
      </ul>
    </main>
  )
}
