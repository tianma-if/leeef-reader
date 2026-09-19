import { useRef, useState } from 'react'
import { isTxtFilename, txtToEpub } from './lib/txtToEpub'
import { ReaderView } from './reader/ReaderView'
import './App.css'

type OpenBook = {
  name: string
  bytes: Uint8Array
}

function App() {
  const inputRef = useRef<HTMLInputElement>(null)
  const [book, setBook] = useState<OpenBook | null>(null)
  const [error, setError] = useState<string | null>(null)

  const openFile = async (file: File) => {
    setError(null)
    const buffer = new Uint8Array(await file.arrayBuffer())
    try {
      if (isTxtFilename(file.name)) {
        setBook({ name: file.name.replace(/\.txt$/i, '.epub'), bytes: txtToEpub(buffer, file.name) })
        return
      }
      setBook({ name: file.name, bytes: buffer })
    } catch (cause) {
      setError(String(cause))
    }
  }

  if (book) {
    return (
      <ReaderView
        fileName={book.name}
        bytes={book.bytes}
        onClose={() => setBook(null)}
      />
    )
  }

  return (
    <main className="library">
      <h1>Leeef Reader</h1>
      <p>打开 EPUB、TXT、MOBI、AZW3 或 FB2。TXT 会先转成 EPUB，再走同一套分页翻页。</p>
      <button type="button" onClick={() => inputRef.current?.click()}>
        打开书籍
      </button>
      <input
        ref={inputRef}
        hidden
        type="file"
        accept=".epub,.txt,.mobi,.azw3,.fb2,.md"
        onChange={(event) => {
          const file = event.target.files?.[0]
          event.target.value = ''
          if (file) void openFile(file)
        }}
      />
      {error ? <p className="reader-error">{error}</p> : null}
    </main>
  )
}

export default App
