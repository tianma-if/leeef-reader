import { useEffect, useState } from 'react'
import { AiScreen } from './ai/AiScreen'
import { api, type Book } from './api'
import { LibraryScreen } from './library/LibraryScreen'
import { NotesScreen } from './notes/NotesScreen'
import { OpdsScreen } from './opds/OpdsScreen'
import { ReaderView } from './reader/ReaderView'
import { SettingsScreen } from './settings/SettingsScreen'
import { StatsScreen } from './stats/StatsScreen'
import './App.css'

type Tab = 'library' | 'notes' | 'stats' | 'opds' | 'ai' | 'settings'

function App() {
  const [tab, setTab] = useState<Tab>('library')
  const [open, setOpen] = useState<Book | null>(null)
  const [books, setBooks] = useState<Book[]>([])

  useEffect(() => {
    void api.listBooks().then(setBooks).catch(() => undefined)
  }, [open, tab])

  if (open) {
    return (
      <ReaderView
        book={open}
        onClose={() => {
          setOpen(null)
          void api.listBooks().then(setBooks)
        }}
      />
    )
  }

  return (
    <div className="app">
      <nav className="dock">
        {(
          [
            ['library', '书架'],
            ['notes', '笔记'],
            ['stats', '统计'],
            ['opds', 'OPDS'],
            ['ai', 'AI'],
            ['settings', '设置'],
          ] as const
        ).map(([id, label]) => (
          <button
            key={id}
            type="button"
            className={tab === id ? 'active' : ''}
            onClick={() => setTab(id)}
          >
            {label}
          </button>
        ))}
      </nav>
      <div className="app-main">
        {tab === 'library' ? (
          <LibraryScreen onOpen={setOpen} />
        ) : null}
        {tab === 'notes' ? (
          <NotesScreen
            onOpenBook={(id) => {
              const book = books.find((item) => item.id === id)
              if (book) setOpen(book)
            }}
          />
        ) : null}
        {tab === 'stats' ? <StatsScreen /> : null}
        {tab === 'opds' ? <OpdsScreen /> : null}
        {tab === 'ai' ? <AiScreen /> : null}
        {tab === 'settings' ? <SettingsScreen /> : null}
      </div>
    </div>
  )
}

export default App
