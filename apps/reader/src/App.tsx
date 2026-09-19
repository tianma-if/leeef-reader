import { useState } from 'react'
import { LibraryScreen } from './library/LibraryScreen'
import type { LibraryBook } from './library/store'
import { ReaderView } from './reader/ReaderView'
import './App.css'

function App() {
  const [open, setOpen] = useState<LibraryBook | null>(null)

  if (open) {
    return <ReaderView book={open} onClose={() => setOpen(null)} />
  }

  return <LibraryScreen onOpen={setOpen} />
}

export default App
