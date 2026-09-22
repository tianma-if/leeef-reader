import { lazy, Suspense, useEffect, useState } from 'react'
import {
  BarChart3,
  BookOpen,
  Bot,
  Rss,
  Settings,
  StickyNote,
} from 'lucide-react'
import { api, type Book } from './api'
import { Button } from '@/components/ui/button'
import { LibraryScreen } from './library/LibraryScreen'
import { NotesScreen } from './notes/NotesScreen'
import { OpdsScreen } from './opds/OpdsScreen'
import { ReaderView } from './reader/ReaderView'
import { SettingsScreen } from './settings/SettingsScreen'
import { StatsScreen } from './stats/StatsScreen'
import { UpdateCoordinator } from './update/UpdateCoordinator'
import './App.css'

const AiScreen = lazy(() =>
  import('./ai/AiScreen').then((module) => ({ default: module.AiScreen })),
)

type Tab = 'library' | 'notes' | 'stats' | 'opds' | 'ai' | 'settings'

const tabs: { id: Tab; label: string; icon: typeof BookOpen }[] = [
  { id: 'library', label: '书架', icon: BookOpen },
  { id: 'notes', label: '笔记', icon: StickyNote },
  { id: 'stats', label: '统计', icon: BarChart3 },
  { id: 'opds', label: 'OPDS', icon: Rss },
  { id: 'ai', label: 'AI', icon: Bot },
  { id: 'settings', label: '设置', icon: Settings },
]

function App() {
  const [tab, setTab] = useState<Tab>('library')
  const [open, setOpen] = useState<Book | null>(null)
  const [openLocator, setOpenLocator] = useState<string | undefined>()
  const [books, setBooks] = useState<Book[]>([])

  useEffect(() => {
    void api.listBooks().then(setBooks).catch(() => undefined)
  }, [open, tab])

  useEffect(() => {
    const hrefs = ['/vendor/foliate-js/view.js', '/vendor/foliate-js/paginator.js']
    for (const href of hrefs) {
      if (document.querySelector(`link[href="${href}"]`)) continue
      const link = document.createElement('link')
      link.rel = 'modulepreload'
      link.href = href
      document.head.append(link)
    }
  }, [])

  useEffect(() => {
    const synchronizeOnResume = () => {
      if (document.visibilityState !== 'visible') return
      void api.settingsSyncStatus()
        .then((status) => status.paired && status.autoSync ? api.settingsSyncNow() : undefined)
        .catch(() => undefined)
    }
    document.addEventListener('visibilitychange', synchronizeOnResume)
    window.addEventListener('online', synchronizeOnResume)
    return () => {
      document.removeEventListener('visibilitychange', synchronizeOnResume)
      window.removeEventListener('online', synchronizeOnResume)
    }
  }, [])

  return (
    <>
      <UpdateCoordinator />
      {open ? (
        <ReaderView
          book={open}
          initialLocator={openLocator}
          onClose={() => {
            setOpen(null)
            setOpenLocator(undefined)
            void api.listBooks().then(setBooks)
          }}
        />
      ) : (
        <div className="flex h-full min-h-0 flex-col bg-background md:flex-row">
          <nav className="order-2 flex border-t bg-card md:order-0 md:w-20 md:flex-col md:border-t-0 md:border-r">
            {tabs.map((item) => {
              const Icon = item.icon
              return (
                <Button
                  key={item.id}
                  type="button"
                  variant={tab === item.id ? 'secondary' : 'ghost'}
                  className="h-auto flex-1 flex-col gap-1 rounded-none py-3 md:flex-none"
                  onClick={() => setTab(item.id)}
                >
                  <Icon className="size-4" />
                  <span className="text-[0.7rem]">{item.label}</span>
                </Button>
              )
            })}
          </nav>
          <div className="min-h-0 flex-1 overflow-y-auto">
            {tab === 'library' ? (
              <LibraryScreen
                onOpen={(book) => {
                  setOpenLocator(undefined)
                  setOpen(book)
                }}
              />
            ) : null}
            {tab === 'notes' ? (
              <NotesScreen
                onOpenBook={(id, locator) => {
                  const book = books.find((item) => item.id === id)
                  if (book) {
                    setOpenLocator(locator)
                    setOpen(book)
                  }
                }}
              />
            ) : null}
            {tab === 'stats' ? <StatsScreen /> : null}
            {tab === 'opds' ? <OpdsScreen /> : null}
            {tab === 'ai' ? (
              <Suspense fallback={<p className="text-muted-foreground px-4 pt-8">加载 AI…</p>}>
                <AiScreen onNavigateToSettings={() => setTab('settings')} />
              </Suspense>
            ) : null}
            {tab === 'settings' ? <SettingsScreen /> : null}
          </div>
        </div>
      )}
    </>
  )
}

export default App
