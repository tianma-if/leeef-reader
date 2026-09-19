import { useEffect, useRef, useState } from 'react'
import { api, isMobile, type Book, type Bookmark, type Excerpt, type Settings } from '../api'
import { CapturedPageTurn } from './capturedTurn'

type Props = {
  book: Book
  onClose: () => void
}

type TocItem = { label?: unknown; href?: string; subitems?: TocItem[] }
type Panel = 'none' | 'toc' | 'search' | 'marks' | 'theme'

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

const waitForSize = (element: HTMLElement) =>
  new Promise<void>((resolve) => {
    if (element.clientWidth > 0 && element.clientHeight > 0) {
      resolve()
      return
    }
    const observer = new ResizeObserver(() => {
      if (element.clientWidth > 0 && element.clientHeight > 0) {
        observer.disconnect()
        resolve()
      }
    })
    observer.observe(element)
  })

const labelOf = (value: unknown): string => {
  if (typeof value === 'string') return value
  if (Array.isArray(value)) return labelOf(value[0])
  return ''
}

const themes: Record<string, { fg: string; bg: string }> = {
  paper: { fg: '#292b29', bg: '#fbf8f1' },
  sepia: { fg: '#5b4636', bg: '#f4ecd8' },
  night: { fg: '#d6d6d6', bg: '#121212' },
}

export function ReaderView({ book, onClose }: Props) {
  const hostRef = useRef<HTMLDivElement>(null)
  const viewRef = useRef<FoliateViewElement | null>(null)
  const started = useRef(Date.now())
  const dragRef = useRef<{
    startX: number
    width: number
    forward: boolean
    session: Awaited<ReturnType<CapturedPageTurn['beginDrag']>>
  } | null>(null)
  const [title, setTitle] = useState(book.title)
  const [progress, setProgress] = useState(book.progress)
  const [chapter, setChapter] = useState(book.chapterTitle ?? '')
  const [error, setError] = useState<string | null>(null)
  const [status, setStatus] = useState('正在打开…')
  const [panel, setPanel] = useState<Panel>('none')
  const [toc, setToc] = useState<TocItem[]>([])
  const [query, setQuery] = useState('')
  const [hits, setHits] = useState<{ cfi?: string; excerpt?: string }[]>([])
  const [bookmarks, setBookmarks] = useState<Bookmark[]>([])
  const [excerpts, setExcerpts] = useState<Excerpt[]>([])
  const [settings, setSettings] = useState<Settings>({})
  const mobile = isMobile()

  const locator = () => viewRef.current?.lastLocation?.cfi ?? book.locator ?? ''

  const reloadMarks = () => {
    void api.listBookmarks(book.id).then(setBookmarks)
    void api.listExcerpts(book.id).then(setExcerpts)
  }

  useEffect(() => {
    void api.getSettings().then(setSettings)
    reloadMarks()
    const host = hostRef.current
    if (!host) return
    let cancelled = false
    let view: FoliateViewElement | null = null

    const start = async () => {
      const bytes = await api.bookBytes(book.id)
      await loadFoliate()
      if (cancelled) return
      await waitForSize(host)
      if (cancelled) return
      view = document.createElement('foliate-view')
      const flow = settings.flow ?? 'paginated'
      view.setAttribute('flow', flow)
      view.setAttribute('max-column-count', String(settings.columns ?? 1))
      view.setAttribute('margin', '24px')
      view.setAttribute('max-block-size', '10000px')
      if (mobile && flow === 'paginated') view.setAttribute('no-swipe', '')
      else if (!mobile && flow === 'paginated') view.setAttribute('animated', '')
      host.append(view)
      viewRef.current = view
      view.addEventListener('relocate', ((event: Event) => {
        const detail = (event as CustomEvent).detail as {
          cfi?: string
          fraction?: number
          tocItem?: { label?: string }
        }
        const fraction = Number(detail.fraction ?? 0)
        setProgress(fraction)
        setChapter(detail.tocItem?.label ?? '')
        void api.saveProgress(book.id, detail.cfi ?? '', fraction, detail.tocItem?.label)
      }) as EventListener)
      view.addEventListener('load', ((event: Event) => {
        const doc = (event as CustomEvent).detail?.doc as Document | undefined
        if (!doc) return
        doc.addEventListener('mouseup', () => {
          const text = doc.getSelection()?.toString().trim()
          if (text) (view as HTMLElement).dataset.selection = text
        })
      }) as EventListener)
      const copy = new Uint8Array(bytes.byteLength)
      copy.set(bytes)
      await view.open(
        new File([new Blob([copy])], book.title + '.epub', {
          type: book.mediaType || 'application/epub+zip',
        }),
      )
      if (cancelled) return
      setToc(view.book?.toc ?? [])
      const metaTitle = view.book?.metadata?.title
      if (typeof metaTitle === 'string' && metaTitle.trim()) setTitle(metaTitle)
      await view.init({
        lastLocation: book.locator,
        showTextStart: !book.locator,
      })
      if (!cancelled) setStatus('')
    }

    start().catch((cause) => {
      if (!cancelled) {
        setStatus('')
        setError(String(cause))
      }
    })

    return () => {
      cancelled = true
      const seconds = Math.round((Date.now() - started.current) / 1000)
      if (seconds >= 5) void api.recordSession(book.id, seconds)
      viewRef.current = null
      view?.close()
      view?.remove()
    }
  }, [book.id])

  const controller = () =>
    new CapturedPageTurn({
      getHostElement: () => hostRef.current,
      getContentRect: () => hostRef.current?.getBoundingClientRect() ?? null,
      navigate: async (forward) => {
        const view = viewRef.current
        if (!view) return
        await (forward ? view.next() : view.prev())
      },
    })

  const turn = (forward: boolean) => {
    const view = viewRef.current
    if (!view) return
    if (mobile && (settings.flow ?? 'paginated') === 'paginated') {
      void controller()
        .turn(forward)
        .catch(() => {
          void (forward ? view.next() : view.prev())
        })
      return
    }
    void (forward ? view.next() : view.prev())
  }

  const speak = () => {
    const text =
      (viewRef.current as HTMLElement | null)?.dataset.selection ||
      chapter ||
      title
    window.speechSynthesis.cancel()
    const utter = new SpeechSynthesisUtterance(text)
    utter.rate = settings.ttsRate ?? 1
    window.speechSynthesis.speak(utter)
  }

  const theme = themes[settings.theme ?? 'paper']

  return (
    <div className="reader-shell" style={{ color: theme.fg, background: theme.bg }}>
      <header className="reader-chrome">
        <button type="button" onClick={onClose}>
          书架
        </button>
        <strong>{title}</strong>
        <span>{(progress * 100).toFixed(1)}%</span>
        <button type="button" onClick={() => setPanel(panel === 'toc' ? 'none' : 'toc')}>
          目录
        </button>
        <button type="button" onClick={() => setPanel(panel === 'search' ? 'none' : 'search')}>
          搜索
        </button>
        <button type="button" onClick={() => setPanel(panel === 'marks' ? 'none' : 'marks')}>
          书签
        </button>
        <button type="button" onClick={() => setPanel(panel === 'theme' ? 'none' : 'theme')}>
          样式
        </button>
        <button type="button" onClick={speak}>
          朗读
        </button>
      </header>
      <div className="reader-body">
        <div className="reader-stage" ref={hostRef}>
          {status ? <p className="reader-status">{status}</p> : null}
          {mobile && (settings.flow ?? 'paginated') === 'paginated' ? (
            <div
              className="reader-gesture"
              onPointerDown={(event) => {
                if (panel !== 'none') return
                const rect = event.currentTarget.getBoundingClientRect()
                const x = event.clientX - rect.left
                const edge = rect.width * 0.4
                if (x > edge && x < rect.width - edge) return
                const forward = x >= rect.width - edge
                event.currentTarget.setPointerCapture(event.pointerId)
                void controller()
                  .beginDrag(forward)
                  .then((session) => {
                    if (!session) return
                    dragRef.current = {
                      startX: event.clientX,
                      width: rect.width,
                      forward,
                      session,
                    }
                  })
                  .catch(() => {
                    turn(forward)
                  })
              }}
              onPointerMove={(event) => {
                const drag = dragRef.current
                if (!drag?.session) return
                const delta = event.clientX - drag.startX
                const signed = drag.forward ? -delta : delta
                const progress = Math.min(1, Math.max(0, signed / drag.width))
                drag.session.overlayEl.dataset.progress = String(progress)
                drag.session.setProgress(progress)
              }}
              onPointerUp={(event) => {
                const drag = dragRef.current
                if (drag?.session) {
                  dragRef.current = null
                  const progress = Number(drag.session.overlayEl.dataset.progress ?? '0')
                  void drag.session.finish(progress > 0.28)
                  return
                }
                if (panel !== 'none') return
                const rect = event.currentTarget.getBoundingClientRect()
                const ratio = (event.clientX - rect.left) / rect.width
                if (ratio < 0.28) turn(false)
                else if (ratio > 0.72) turn(true)
              }}
            />
          ) : (
            <div
              className="reader-gesture"
              onPointerUp={(event) => {
                if (panel !== 'none') return
                const rect = event.currentTarget.getBoundingClientRect()
                const ratio = (event.clientX - rect.left) / rect.width
                if (ratio < 0.28) turn(false)
                else if (ratio > 0.72) turn(true)
              }}
            />
          )}
        </div>
        {panel !== 'none' ? (
          <aside className="reader-panel">
            {panel === 'toc' ? (
              <nav>
                {toc.map((item) => (
                  <button
                    key={String(item.href)}
                    type="button"
                    onClick={() => item.href && void viewRef.current?.goTo(item.href)}
                  >
                    {labelOf(item.label)}
                  </button>
                ))}
              </nav>
            ) : null}
            {panel === 'search' ? (
              <div>
                <input
                  value={query}
                  onChange={(event) => setQuery(event.target.value)}
                  placeholder="书内搜索"
                  onKeyDown={(event) => {
                    if (event.key === 'Enter' && viewRef.current) {
                      void (async () => {
                        const next: { cfi?: string; excerpt?: string }[] = []
                        for await (const hit of viewRef.current!.search({ query })) {
                          next.push(hit)
                          if (next.length > 40) break
                        }
                        setHits(next)
                      })()
                    }
                  }}
                />
                {hits.map((hit) => (
                  <button
                    key={hit.cfi}
                    type="button"
                    onClick={() => hit.cfi && void viewRef.current?.goTo(hit.cfi)}
                  >
                    {hit.excerpt}
                  </button>
                ))}
              </div>
            ) : null}
            {panel === 'marks' ? (
              <div>
                <button
                  type="button"
                  className="btn"
                  onClick={() =>
                    void api
                      .addBookmark(book.id, locator(), chapter || title)
                      .then(reloadMarks)
                  }
                >
                  添加书签
                </button>
                <button
                  type="button"
                  className="btn"
                  onClick={() => {
                    const quote =
                      (viewRef.current as HTMLElement | null)?.dataset.selection ?? ''
                    if (!quote) return
                    void api
                      .createExcerpt({
                        bookId: book.id,
                        locator: locator(),
                        quote,
                        color: 'yellow',
                      })
                      .then(reloadMarks)
                  }}
                >
                  保存书摘
                </button>
                <h3>书签</h3>
                {bookmarks.map((item) => (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => void viewRef.current?.goTo(item.locator)}
                  >
                    {item.title || item.locator}
                  </button>
                ))}
                <h3>书摘</h3>
                {excerpts.map((item) => (
                  <p key={item.id}>{item.quote}</p>
                ))}
              </div>
            ) : null}
            {panel === 'theme' ? (
              <div>
                {(['paper', 'sepia', 'night'] as const).map((name) => (
                  <button
                    key={name}
                    type="button"
                    onClick={() => {
                      const next = { ...settings, theme: name }
                      setSettings(next)
                      void api.saveSettings(next)
                    }}
                  >
                    {name}
                  </button>
                ))}
              </div>
            ) : null}
          </aside>
        ) : null}
      </div>
      {error ? <p className="reader-error">{error}</p> : null}
    </div>
  )
}
