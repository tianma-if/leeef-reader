import { api, type Book } from '../api'

let foliateLoaded: Promise<void> | undefined

export function loadFoliate() {
  if (customElements.get('foliate-view')) return Promise.resolve()
  foliateLoaded ??= new Promise<void>((resolve, reject) => {
    const script = document.createElement('script')
    script.type = 'module'
    script.src = '/vendor/foliate-js/view.js'
    script.onload = () => resolve()
    script.onerror = () => {
      script.remove()
      foliateLoaded = undefined
      reject(new Error('无法加载阅读引擎'))
    }
    document.head.append(script)
  })
  return foliateLoaded
}

export async function loadBookSource(book: Book) {
  const type = book.mediaType || 'application/epub+zip'
  const name = `${book.title}.epub`
  if (book.filePath) {
    try {
      const response = await fetch(api.bookFileUrl(book.filePath))
      if (response.ok) return new File([await response.blob()], name, { type })
    } catch {
      // Fall through to the binary IPC path.
    }
  }
  const bytes = await api.bookBytes(book.id)
  return new File([bytes], name, { type })
}
