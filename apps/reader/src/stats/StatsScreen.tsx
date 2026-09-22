import { useEffect, useMemo, useState } from 'react'
import {
  BookCheck,
  BookOpen,
  Calendar,
  Clock,
  Flame,
  TrendingUp,
} from 'lucide-react'
import { api, type Book, type Session } from '../api'
import { countReadingDays } from './readingDays'
import { useLibraryRefresh } from '../lib/useLibraryRefresh'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

export function StatsScreen() {
  const [sessions, setSessions] = useState<Session[]>([])
  const [books, setBooks] = useState<Book[]>([])

  useEffect(() => {
    void Promise.all([api.listSessions(), api.listBooks()]).then(
      ([nextSessions, nextBooks]) => {
        setSessions(nextSessions)
        setBooks(nextBooks)
      },
    )
  }, [])

  useLibraryRefresh(async () => {
    const [nextSessions, nextBooks] = await Promise.all([api.listSessions(), api.listBooks()])
    setSessions(nextSessions)
    setBooks(nextBooks)
  })

  const totalSeconds = sessions.reduce((sum, item) => sum + item.durationSeconds, 0)
  const totalMinutes = Math.round(totalSeconds / 60)
  const totalHours = (totalMinutes / 60).toFixed(1)
  const days = countReadingDays(sessions)
  const finishedBooks = books.filter((book) => book.progress >= 0.999).length

  const byBook = useMemo(() => {
    const map = new Map<string, number>()
    for (const session of sessions) {
      map.set(session.bookId, (map.get(session.bookId) ?? 0) + session.durationSeconds)
    }
    return [...map.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 6)
      .map(([id, seconds]) => ({
        id,
        title: books.find((book) => book.id === id)?.title ?? id,
        author: books.find((book) => book.id === id)?.author,
        seconds,
        minutes: Math.round(seconds / 60),
      }))
  }, [sessions, books])

  const maxBookSeconds = byBook[0]?.seconds || 1

  const cards = [
    {
      label: '累计阅读',
      value: totalHours,
      unit: '小时',
      subtext: `${totalMinutes} 分钟`,
      icon: Clock,
      color: 'text-amber-500',
    },
    {
      label: '阅读天数',
      value: days,
      unit: '天',
      subtext: '坚持日常阅读',
      icon: Calendar,
      color: 'text-emerald-500',
    },
    {
      label: '书库藏书',
      value: books.length,
      unit: '本',
      subtext: `${books.filter((b) => b.progress > 0.01 && b.progress < 0.999).length} 本在读`,
      icon: BookOpen,
      color: 'text-blue-500',
    },
    {
      label: '已读完',
      value: finishedBooks,
      unit: '本',
      subtext: books.length > 0 ? `完读率 ${Math.round((finishedBooks / books.length) * 100)}%` : '0%',
      icon: BookCheck,
      color: 'text-rose-500',
    },
  ]

  return (
    <main className="px-4 pt-4 pb-8 max-w-4xl mx-auto">
      <header className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="font-heading text-2xl">阅读统计</h1>
          <p className="text-xs text-muted-foreground mt-0.5">记录你的阅读旅程与成长轨迹</p>
        </div>
        <div className="flex items-center gap-1 text-xs text-muted-foreground bg-muted/60 px-3 py-1.5 rounded-full">
          <Flame className="size-3.5 text-amber-500 fill-amber-500" />
          <span>阅读习惯培养中</span>
        </div>
      </header>

      {/* Metric Cards Grid */}
      <div className="mb-8 grid grid-cols-2 gap-3 sm:grid-cols-4">
        {cards.map((card) => {
          const Icon = card.icon
          return (
            <Card key={card.label} size="sm" className="relative overflow-hidden">
              <CardHeader className="flex flex-row items-center justify-between pb-1">
                <CardTitle className="text-muted-foreground text-xs font-medium">
                  {card.label}
                </CardTitle>
                <Icon className={`size-4 ${card.color}`} />
              </CardHeader>
              <CardContent className="space-y-1">
                <div className="flex items-baseline gap-1">
                  <span className="text-2xl font-bold tracking-tight">{card.value}</span>
                  <span className="text-xs text-muted-foreground font-medium">{card.unit}</span>
                </div>
                <p className="text-[11px] text-muted-foreground">{card.subtext}</p>
              </CardContent>
            </Card>
          )
        })}
      </div>

      {/* Top Read Books - Horizontal Visualized Bars */}
      <section className="rounded-xl border border-border/70 bg-card p-5 shadow-xs">
        <div className="mb-4 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <TrendingUp className="size-4 text-primary" />
            <h2 className="text-base font-semibold">阅读时长排行</h2>
          </div>
          <span className="text-xs text-muted-foreground">TOP {byBook.length}</span>
        </div>

        {byBook.length === 0 ? (
          <div className="py-8 text-center text-muted-foreground text-xs">
            暂无阅读时长数据，打开一本书开始阅读吧。
          </div>
        ) : (
          <div className="space-y-4">
            {byBook.map((item, index) => {
              const percentage = Math.max(5, Math.round((item.seconds / maxBookSeconds) * 100))
              return (
                <div key={item.id} className="space-y-1.5">
                  <div className="flex items-center justify-between text-xs">
                    <div className="flex items-center gap-2 min-w-0 pr-2">
                      <span className="grid size-4 shrink-0 place-items-center rounded-full bg-muted text-[10px] font-bold text-muted-foreground font-mono">
                        {index + 1}
                      </span>
                      <strong className="truncate font-medium">{item.title}</strong>
                      {item.author ? (
                        <span className="text-muted-foreground truncate hidden sm:inline">
                          · {item.author}
                        </span>
                      ) : null}
                    </div>
                    <span className="shrink-0 font-mono text-muted-foreground">
                      {item.minutes >= 60
                        ? `${(item.minutes / 60).toFixed(1)} 小时`
                        : `${item.minutes} 分钟`}
                    </span>
                  </div>

                  {/* Visual Bar */}
                  <div className="h-2 w-full rounded-full bg-muted/60 overflow-hidden">
                    <div
                      className="h-full rounded-full bg-gradient-to-r from-primary/80 to-primary transition-all duration-500"
                      style={{ width: `${percentage}%` }}
                    />
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </section>
    </main>
  )
}
