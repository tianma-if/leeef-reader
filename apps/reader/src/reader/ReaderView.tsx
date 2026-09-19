import { useEffect, useRef, useState } from 'react'
import type { LibraryBook } from '../library/store'
import { getBookFile, saveProgress } from '../library/store'
import { isMobileShell } from './nativeCapture'

type Props = {
  book: LibraryBook
  onClose: () => void
}

const loadFoliate = () =>
  new Promise<void>((resolve, reject) => {
    if (customElements.get('foliate-view')) {
      resolve()
      return
    }
    const script = document.createElement('script')
    script.type = 'module'
    script.src = '/vendor/foliate-js/view.js'
    script.onload = () => resolve()
    script.onerror = () => reject(new Error('无法加载阅读引擎'))
    document.head.append(script)
  })

export function ReaderView({ book, onClose }: Props) {
  const hostRef = useRef<HTMLDivElement>(null)
  const viewRef = useRef<FoliateViewElement | null>(null)
  const [title, setTitle] = useState(book.title)
  const [progress, setProgress] = useState(book.progress)
  const [error, setError] = useState<string | null>(null)
  const mobile = isMobileShell()

  useEffect(() => {
    const host = hostRef.current
    if (!host) return
    let cancelled = false
    let view: FoliateViewElement | null = null

    const start = async () => {
      const bytes = await getBookFile(book.id)
      if (!bytes) throw new Error('找不到书籍文件')
      await loadFoliate()
      if (cancelled) return
      view = document.createElement('foliate-view')
      view.setAttribute('flow', 'paginated')
      view.setAttribute('max-column-count', '1')
      view.setAttribute('margin', '24px')
      view.setAttribute('max-block-size', '10000px')
      if (!mobile) view.setAttribute('animated', '')
      host.append(view)
      viewRef.current = view
      view.addEventListener('relocate', ((event: Event) => {
        const detail = (event as CustomEvent).detail as {
          cfi?: string
          fraction?: number
        }
        const fraction = Number(detail.fraction ?? 0)
        setProgress(fraction)
        void saveProgress(book.id, fraction, detail.cfi ?? null)
      }) as EventListener)
      const copy = new Uint8Array(bytes.byteLength)
      copy.set(bytes)
      await view.open(new File([new Blob([copy])], book.fileName))
      const metaTitle = view.book?.metadata?.title
      if (typeof metaTitle === 'string' && metaTitle.trim()) setTitle(metaTitle)
      await view.init({
        lastLocation: book.locator,
        showTextStart: !book.locator,
      })
    }

    start().catch((cause) => {
      if (!cancelled) setError(String(cause))
    })

    return () => {
      cancelled = true
      viewRef.current = null
      view?.close()
      view?.remove()
    }
  }, [book, mobile])

  const turn = (forward: boolean) => {
    const view = viewRef.current
    if (!view) return
    void (forward ? view.next() : view.prev())
  }

  const onTap = (event: React.PointerEvent<HTMLDivElement>) => {
    if (event.pointerType === 'mouse' && event.button !== 0) return
    const rect = event.currentTarget.getBoundingClientRect()
    const x = event.clientX - rect.left
    const ratio = x / rect.width
    if (ratio < 0.28) turn(false)
    else if (ratio > 0.72) turn(true)
  }

  return (
    <div className="reader-shell">
      <header className="reader-chrome">
        <button type="button" onClick={onClose}>
          书架
        </button>
        <strong>{title}</strong>
        <span>{(progress * 100).toFixed(1)}%</span>
      </header>
      <div
        className="reader-stage"
        ref={hostRef}
        onPointerUp={onTap}
      />
      {error ? <p className="reader-error">{error}</p> : null}
    </div>
  )
}
