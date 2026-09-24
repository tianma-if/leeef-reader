import { lazy, Suspense, useCallback, useEffect, useRef, useState, type PointerEvent } from 'react'
import { listen } from '@tauri-apps/api/event'
import { toast } from 'sonner'
import {
  api,
  isMobile,
  type Book,
  type Bookmark,
  type Excerpt,
  type Settings,
} from '../api'
import { applyReadingFont, applyViewLayout, highlightDraw, themeOf } from './bookStyles'
import { normalizeSelectedText } from './selectionText'
import { mountReadingFont } from './fontLoader'
import { CapturedPageTurn } from './capturedTurn'
import { TurnQueue } from './turnQueue'
import { ReaderChrome } from './ReaderChrome'
import { ReaderFooter } from './ReaderFooter'
import { ReaderSidebar } from './ReaderSidebar'
import { SelectionPopup, type SelectionState } from './SelectionPopup'
import {
  releaseVelocity,
  shouldCommitTurn,
  TAP_SLOP_PX,
  zoneOf,
} from './turnCommit'
import {
  createTurnGestureIntent,
  edgeDirectionOf,
  shouldClaimTurnGesture,
  type TurnGestureIntent,
} from './turnGestureArena'
import { useReaderChrome } from './useReaderChrome'
import { createReadingTimer } from './readingTimer'
import { createWheelTurnState, wheelTurnDirection } from './wheelTurn'
import { useLibraryRefresh } from '../lib/useLibraryRefresh'
import type { ReadingSource } from '../ai/selectionAgent'

const ReaderAiPanel = lazy(() => import('./ReaderAiPanel').then((module) => ({ default: module.ReaderAiPanel })))

type Props = {
  book: Book
  onClose: () => void
  initialLocator?: string
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

const loadBookSource = async (book: Book) => {
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

export function ReaderView({ book, onClose, initialLocator }: Props) {
  const hostRef = useRef<HTMLDivElement>(null)
  const viewRef = useRef<FoliateViewElement | null>(null)
  const excerptsRef = useRef<Excerpt[]>([])
  const settingsRef = useRef<Settings>({})
  const saveTimer = useRef<number>(0)
  const prepareTimer = useRef<number>(0)
  const dragRef = useRef<{
    pointerId: number
    startX: number
    startY: number
    originX: number
    visualOrigin: number
    left: number
    width: number
    claimed: boolean
    vertical: boolean
    forward: boolean
    intent: TurnGestureIntent
    samples: { distance: number; time: number }[]
  } | null>(null)
  const turner = useRef<CapturedPageTurn | null>(null)
  const turnQueue = useRef<TurnQueue | null>(null)
  turnQueue.current ??= new TurnQueue((error) => {
    console.error('Page turn failed', error)
    toast.error('翻页失败，请重试')
  })

  const [title, setTitle] = useState(book.title)
  const [progress, setProgress] = useState(book.progress)
  const [chapter, setChapter] = useState(book.chapterTitle ?? '')
  const [locator, setLocator] = useState(book.locator ?? '')
  const [error, setError] = useState<string | null>(null)
  const [status, setStatus] = useState('正在打开…')
  const [toc, setToc] = useState<TocItem[]>([])
  const [query, setQuery] = useState('')
  const [hits, setHits] = useState<{ cfi?: string; excerpt?: string }[]>([])
  const [bookmarks, setBookmarks] = useState<Bookmark[]>([])
  const [excerpts, setExcerpts] = useState<Excerpt[]>([])
  const [settings, setSettings] = useState<Settings>({})
  const [selection, setSelection] = useState<SelectionState | null>(null)
  const [aiSource, setAiSource] = useState<ReadingSource | null>(null)
  const mobile = isMobile()
  const chrome = useReaderChrome()
  const chromeRef = useRef(chrome)
  chromeRef.current = chrome
  const paginated = (settings.flow ?? 'paginated') === 'paginated'
  const theme = themeOf(settings)
  const bookmarked = bookmarks.some((item) => item.locator === locator)

  const getTurner = () => {
    turner.current ??= new CapturedPageTurn({
      getHostElement: () => hostRef.current,
      getContentRect: () => hostRef.current?.getBoundingClientRect() ?? null,
      navigate: async (forward) => {
        const view = viewRef.current
        if (!view) return false
        const before = view.lastLocation?.cfi
        const renderer = view.renderer
        const hadAnimated = renderer?.hasAttribute('animated')
        renderer?.removeAttribute('animated')
        try {
          await (forward ? view.next() : view.prev())
          return view.lastLocation?.cfi !== before
        } finally {
          if (hadAnimated) renderer?.setAttribute('animated', '')
        }
      },
    })
    return turner.current
  }

  const reloadMarks = useCallback(async () => {
    const [nextBookmarks, nextExcerpts] = await Promise.all([
      api.listBookmarks(book.id),
      api.listExcerpts(book.id),
    ])
    setBookmarks(nextBookmarks)
    setExcerpts(nextExcerpts)
    excerptsRef.current = nextExcerpts
  }, [book.id])

  const paintHighlights = useCallback((view: FoliateViewElement) => {
    for (const item of excerptsRef.current) {
      void view.addAnnotation({ value: item.locator, color: item.color || '#c4a35a' })
    }
  }, [])

  const patchSettings = (partial: Partial<Settings>) => {
    setSettings((current) => {
      const next = { ...current, ...partial }
      settingsRef.current = next
      window.clearTimeout(saveTimer.current)
      saveTimer.current = window.setTimeout(() => {
        void api.saveSettings(next)
      }, 280)
      const view = viewRef.current
      if (view) {
        applyViewLayout(view, next, mobile)
        void applyReadingFont(view, next)
      }
      return next
    })
  }

  const turn = (forward: boolean) => {
    const view = viewRef.current
    if (!view) return
    chromeRef.current.hide()
    if (dragRef.current?.claimed) return
    turnQueue.current!.run(async () => {
      if (viewRef.current !== view) return
      const useCapture =
        isMobile() && (settingsRef.current.flow ?? 'paginated') === 'paginated'
      const started = useCapture && await getTurner().turn(forward)
      if (!started && viewRef.current === view) await (forward ? view.next() : view.prev())
      if (viewRef.current === view && useCapture) void getTurner().prepare()
    })
  }
  const turnRef = useRef(turn)
  turnRef.current = turn

  useEffect(() => {
    if (mobile) return
    const stage = hostRef.current
    if (!stage) return
    const wheelState = createWheelTurnState()
    const onWheel = (event: WheelEvent) => {
      if ((settingsRef.current.flow ?? 'paginated') !== 'paginated' || !viewRef.current) return
      if (event.ctrlKey || event.metaKey) return
      if (event.deltaY === 0 || Math.abs(event.deltaY) <= Math.abs(event.deltaX)) return
      event.preventDefault()
      const direction = wheelTurnDirection(wheelState, event, stage.clientHeight)
      if (direction === null) return
      turnRef.current(direction)
    }
    stage.addEventListener('wheel', onWheel, { passive: false })
    return () => stage.removeEventListener('wheel', onWheel)
  }, [mobile])

  const goTo = (target: string) => {
    void viewRef.current?.goTo(target)
    chrome.closeSidebar()
    setSelection(null)
  }

  const lastSuggestedLocator = useRef('')
  useLibraryRefresh(async () => {
    await reloadMarks()
    const remote = (await api.listBooks()).find((item) => item.id === book.id)
    if (remote?.locator && remote.locator !== locator && remote.locator !== lastSuggestedLocator.current) {
      lastSuggestedLocator.current = remote.locator
      toast('阅读位置已有更新', {
        description: remote.chapterTitle || `进度 ${Math.round(remote.progress * 100)}%`,
        action: { label: '接续阅读', onClick: () => goTo(remote.locator!) },
      })
    }
  })

  useEffect(() => {
    excerptsRef.current = excerpts
  }, [excerpts])

  useEffect(() => {
    void reloadMarks()
    const host = hostRef.current
    if (!host) return
    let cancelled = false
    let view: FoliateViewElement | null = null
    let ready = false
    const readingTimer = createReadingTimer((seconds) => api.recordSession(book.id, seconds))
    const flushReadingTime = () => {
      void readingTimer.flush().catch(() => toast.error('阅读时长保存失败，将在下次记录时重试'))
    }
    const onVisibility = () => {
      readingTimer.setActive(ready && document.visibilityState === 'visible')
      flushReadingTime()
    }
    const onPageHide = () => {
      readingTimer.setActive(false)
      flushReadingTime()
    }
    document.addEventListener('visibilitychange', onVisibility)
    window.addEventListener('pagehide', onPageHide)
    window.addEventListener('pageshow', onVisibility)
    const readingInterval = window.setInterval(flushReadingTime, 30_000)

    const start = async () => {
      const [loaded, source] = await Promise.all([
        api.getSettings(),
        loadBookSource(book),
        loadFoliate(),
      ])
      if (cancelled) return
      settingsRef.current = loaded
      setSettings(loaded)
      void mountReadingFont(document, loaded.fontFamily).catch(() => undefined)
      await waitForSize(host)
      if (cancelled) return
      view = document.createElement('foliate-view')
      host.append(view)
      viewRef.current = view
      view.addEventListener('relocate', ((event: Event) => {
        setStatus('')
        const detail = (event as CustomEvent).detail as {
          cfi?: string
          fraction?: number
          tocItem?: { label?: string }
        }
        const fraction = Number(detail.fraction ?? 0)
        setProgress(fraction)
        setChapter(detail.tocItem?.label ?? '')
        setLocator(detail.cfi ?? '')
        void api.saveProgress(book.id, detail.cfi ?? '', fraction, detail.tocItem?.label)
        getTurner().invalidate()
        window.clearTimeout(prepareTimer.current)
        if (isMobile() && (settingsRef.current.flow ?? 'paginated') === 'paginated') {
          prepareTimer.current = window.setTimeout(() => {
            void getTurner().prepare()
          }, 160)
        }
      }) as EventListener)
      view.addEventListener('draw-annotation', ((event: Event) => {
        const detail = (event as CustomEvent).detail as {
          draw: (fn: typeof highlightDraw, options: { color?: string }) => void
          annotation: { color?: string }
        }
        detail.draw(highlightDraw, { color: detail.annotation.color ?? '#c4a35a' })
      }) as EventListener)
      view.addEventListener('create-overlay', (() => {
        if (view) paintHighlights(view)
      }) as EventListener)
      view.addEventListener('load', ((event: Event) => {
        const detail = (event as CustomEvent).detail as { doc?: Document; index?: number }
        const doc = detail.doc
        if (!doc || !view) return
        void applyReadingFont(view, settingsRef.current)
        const index = detail.index ?? 0
        const onPointer = () => {
          const text = normalizeSelectedText(doc.getSelection()?.toString() ?? '')
          const range =
            doc.getSelection()?.rangeCount ? doc.getSelection()!.getRangeAt(0) : null
          if (!text || !range || range.collapsed) {
            setSelection(null)
            return
          }
          const frame = doc.defaultView?.frameElement as HTMLElement | null
          const frameRect = frame?.getBoundingClientRect()
          const rangeRect = range.getBoundingClientRect()
          if (!frameRect) return
          setSelection({
            text,
            cfi: view!.getCFI(index, range),
            x: frameRect.left + rangeRect.left + rangeRect.width / 2,
            y: frameRect.top + Math.max(8, rangeRect.top - 8),
          })
        }
        doc.addEventListener('mouseup', onPointer)
        doc.addEventListener('touchend', onPointer)
        doc.addEventListener('click', (event) => {
          if (doc.getSelection()?.toString().trim()) return
          const ratio = event.clientX / (doc.defaultView?.innerWidth || 1)
          const zone = zoneOf(ratio)
          const ui = chromeRef.current
          if (ui.visible || ui.sidebar) {
            ui.hide()
            ui.closeSidebar()
            return
          }
          if (zone === 'center') ui.toggle()
          else if ((settingsRef.current.flow ?? 'paginated') === 'paginated') {
            turnRef.current(zone === 'right')
          } else ui.toggle()
        })
        doc.addEventListener('touchstart', (event) => {
          const touch = event.changedTouches[0]
          if (!touch) return
          ;(doc.documentElement as HTMLElement).dataset.touchX = String(touch.clientX)
          ;(doc.documentElement as HTMLElement).dataset.touchY = String(touch.clientY)
        })
        doc.addEventListener('touchend', (event) => {
          const touch = event.changedTouches[0]
          if (!touch) return
          const startX = Number((doc.documentElement as HTMLElement).dataset.touchX ?? touch.clientX)
          const startY = Number((doc.documentElement as HTMLElement).dataset.touchY ?? touch.clientY)
          const dx = touch.clientX - startX
          const dy = touch.clientY - startY
          if (dy < -10 && Math.abs(dy) > 2 * Math.abs(dx) && Math.abs(dx) < (doc.defaultView?.innerWidth ?? 1) * 0.3) {
            chromeRef.current.toggle()
          }
        })
        paintHighlights(view)
      }) as EventListener)
      await view.open(source)
      if (cancelled) return
      applyViewLayout(view, loaded, mobile)
      void applyReadingFont(view, loaded)
      setToc(view.book?.toc ?? [])
      const metaTitle = view.book?.metadata?.title
      if (typeof metaTitle === 'string' && metaTitle.trim()) setTitle(metaTitle)
      await view.init({
        lastLocation: initialLocator || book.locator,
        showTextStart: !(initialLocator || book.locator),
      })
      paintHighlights(view)
      if (!cancelled) {
        setStatus('')
        ready = true
        readingTimer.setActive(document.visibilityState === 'visible')
      }
    }

    start().catch((cause) => {
      if (!cancelled) {
        setStatus('')
        setError(String(cause))
      }
    })

    return () => {
      cancelled = true
      window.clearTimeout(prepareTimer.current)
      window.clearTimeout(saveTimer.current)
      turnQueue.current?.clear()
      dragRef.current = null
      window.clearInterval(readingInterval)
      document.removeEventListener('visibilitychange', onVisibility)
      window.removeEventListener('pagehide', onPageHide)
      window.removeEventListener('pageshow', onVisibility)
      readingTimer.setActive(false)
      flushReadingTime()
      getTurner().dispose()
      turner.current = null
      viewRef.current = null
      view?.close()
      view?.remove()
    }
  }, [book.id, initialLocator])

  useEffect(() => {
    let stop: (() => void) | undefined
    void listen('settings-synced', () => {
      void api.getSettings().then((next) => {
        settingsRef.current = next
        setSettings(next)
        const view = viewRef.current
        if (view) {
          applyViewLayout(view, next, mobile)
          void applyReadingFont(view, next)
        }
      })
    }).then((unlisten) => { stop = unlisten })
    return () => stop?.()
  }, [mobile])

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null
      if (target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.isContentEditable)) {
        return
      }
      if (event.key === 'Escape') {
        if (selection) {
          setSelection(null)
          viewRef.current?.deselect()
          return
        }
        if (chrome.sidebar) {
          chrome.closeSidebar()
          return
        }
        if (chrome.visible) {
          chrome.hide()
          return
        }
        onClose()
        return
      }
      if (event.key === 'ArrowLeft' || event.key === 'PageUp') {
        event.preventDefault()
        turn(false)
      }
      if (event.key === 'ArrowRight' || event.key === 'PageDown' || event.key === ' ') {
        event.preventDefault()
        turn(true)
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [chrome, onClose, selection])

  const onGesturePointerDown = (event: PointerEvent<HTMLDivElement>) => {
    if (!event.isPrimary || dragRef.current) return
    if (chrome.visible || chrome.sidebar) {
      chrome.hide()
      chrome.closeSidebar()
      return
    }
    const rect = hostRef.current?.getBoundingClientRect()
    if (!rect) return
    event.currentTarget.setPointerCapture(event.pointerId)
    const now = performance.now()
    const localX = event.clientX - rect.left
    dragRef.current = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      originX: event.clientX,
      visualOrigin: 0,
      left: rect.left,
      width: rect.width,
      claimed: false,
      vertical: false,
      forward: true,
      intent: createTurnGestureIntent(edgeDirectionOf(localX, rect.width), now),
      samples: [{ distance: 0, time: now }],
    }
    if (mobile && paginated) void getTurner().prepare()
  }

  const onGesturePointerMove = (event: PointerEvent<HTMLDivElement>) => {
    const drag = dragRef.current
    if (!drag || drag.pointerId !== event.pointerId) return
    const dx = event.clientX - drag.startX
    const dy = event.clientY - drag.startY
    if (!drag.claimed && !drag.vertical) {
      if (drag.intent.verticalLocked) {
        drag.vertical = true
        return
      }
      const claimed = shouldClaimTurnGesture(drag.intent, {
        deltaX: dx,
        deltaY: dy,
        deltaT: performance.now(),
      })
      if (drag.intent.verticalLocked) {
        drag.vertical = true
        return
      }
      if (claimed && mobile && paginated) {
        if (turnQueue.current?.busy || !getTurner().startDrag(dx < 0)) return
        drag.claimed = true
        drag.forward = dx < 0
        drag.originX = drag.startX
        drag.visualOrigin = Math.max(0, drag.forward ? -dx : dx)
      }
    }
    if (!drag.claimed) return
    const signed = drag.forward ? drag.originX - event.clientX : event.clientX - drag.originX
    const next = Math.min(1, Math.max(0, (signed - drag.visualOrigin) / drag.width))
    getTurner().setProgress(next)
    drag.samples.push({ distance: signed, time: performance.now() })
    if (drag.samples.length > 8) drag.samples.shift()
  }

  const onGesturePointerUp = (event: PointerEvent<HTMLDivElement>) => {
    const drag = dragRef.current
    if (!drag || drag.pointerId !== event.pointerId) return
    dragRef.current = null
    const dx = event.clientX - drag.startX
    const dy = event.clientY - drag.startY
    if (drag.claimed) {
      const signed = drag.forward ? drag.originX - event.clientX : event.clientX - drag.originX
      const progressValue = Math.min(1, Math.max(0, (signed - drag.visualOrigin) / drag.width))
      getTurner().setProgress(progressValue)
      const velocity = releaseVelocity(drag.samples, performance.now())
      const commit =
        event.type === 'pointercancel'
          ? false
          : shouldCommitTurn(progressValue, velocity, drag.width)
      const view = viewRef.current
      const activeTurner = getTurner()
      turnQueue.current!.run(async () => {
        const started = await activeTurner.endDrag(commit)
        if (viewRef.current !== view) return
        if (!started && commit && view) await (drag.forward ? view.next() : view.prev())
        void activeTurner.prepare()
      })
      return
    }
    if (event.type === 'pointercancel') return
    if (chrome.visible || chrome.sidebar) return
    if (drag.vertical || (dy < -10 && Math.abs(dy) > 2 * Math.abs(dx))) {
      chrome.toggle()
      return
    }
    if (Math.hypot(dx, dy) > TAP_SLOP_PX) return
    const zone = zoneOf((event.clientX - drag.left) / drag.width)
    if (zone === 'center') chrome.toggle()
    else if (paginated) turn(zone === 'right')
    else chrome.toggle()
  }

  const toggleBookmark = () => {
    const current = viewRef.current?.lastLocation?.cfi ?? locator
    const existing = bookmarks.find((item) => item.locator === current)
    if (existing) {
      void api.deleteBookmark(existing.id).then(reloadMarks)
      return
    }
    void api.addBookmark(book.id, current, chapter || title).then(reloadMarks)
  }

  return (
    <div
      className={mobile ? 'reader-shell is-mobile' : 'reader-shell'}
      style={{ color: theme.fg, background: theme.bg }}
    >
      <div className="reader-stage" ref={hostRef}>
        {status ? <p className="reader-status">{status}</p> : null}
        {paginated ? (
          <div
            className="reader-gesture"
            onPointerDown={onGesturePointerDown}
            onPointerMove={onGesturePointerMove}
            onPointerUp={onGesturePointerUp}
            onPointerCancel={onGesturePointerUp}
          />
        ) : null}
      </div>

      <ReaderChrome
        title={title}
        chapter={chapter}
        progress={progress}
        visible={chrome.visible}
        bookmarked={bookmarked}
        mobile={mobile}
        onBack={onClose}
        onToggleBookmark={toggleBookmark}
        onOpenSidebar={chrome.openSidebar}
        onKeepVisible={chrome.show}
        onRequestHide={chrome.hide}
      />
      <ReaderFooter
        mobile={mobile}
        visible={chrome.visible}
        footerTab={chrome.footerTab}
        settings={settings}
        progress={progress}
        chapter={chapter}
        onOpenTab={chrome.openTab}
        onPatch={patchSettings}
        onGoToFraction={(value) => void viewRef.current?.goToFraction(value)}
        onTurn={turn}
        onKeepVisible={chrome.show}
        onRequestHide={chrome.hide}
      />
      <ReaderSidebar
        open={chrome.sidebar}
        mobile={mobile}
        toc={toc}
        query={query}
        hits={hits}
        bookmarks={bookmarks}
        excerpts={excerpts}
        settings={settings}
        onPatch={patchSettings}
        onQuery={setQuery}
        onSearch={() => {
          const view = viewRef.current
          if (!view || !query.trim()) return
          void (async () => {
            const next: { cfi?: string; excerpt?: string }[] = []
            for await (const hit of view.search({ query })) {
              next.push(hit)
              if (next.length > 40) break
            }
            setHits(next)
          })()
        }}
        onGo={goTo}
        onAddBookmark={toggleBookmark}
        onDeleteBookmark={(id) => void api.deleteBookmark(id).then(reloadMarks)}
        onClose={chrome.closeSidebar}
      />
      {selection ? (
        <SelectionPopup
          selection={selection}
          onAiExplain={() => {
            if (selection.text.length > 16_000) {
              toast.error('选中文字过长，请缩小到 16,000 字以内再提问')
              return
            }
            setAiSource({ bookTitle: title, chapter, quote: selection.text, locator: selection.cfi })
            setSelection(null)
            chrome.hide()
          }}
          onCopy={() => {
            void navigator.clipboard.writeText(selection.text)
            setSelection(null)
          }}
          onHighlight={(color = '#c4a35a') => {
            void api
              .createExcerpt({
                bookId: book.id,
                locator: selection.cfi,
                quote: selection.text,
                color,
              })
              .then(async () => {
                await reloadMarks()
                void viewRef.current?.addAnnotation({
                  value: selection.cfi,
                  color,
                })
                setSelection(null)
                viewRef.current?.deselect()
              })
          }}
          onSaveNote={(note, color = '#c4a35a') => {
            void api
              .createExcerpt({
                bookId: book.id,
                locator: selection.cfi,
                quote: selection.text,
                note: note.trim() || undefined,
                color,
              })
              .then(async () => {
                await reloadMarks()
                void viewRef.current?.addAnnotation({
                  value: selection.cfi,
                  color,
                })
                setSelection(null)
                viewRef.current?.deselect()
              })
          }}
          onBookmark={() => {
            void api.addBookmark(book.id, selection.cfi, selection.text.slice(0, 40)).then(() => {
              void reloadMarks()
              setSelection(null)
            })
          }}
        />
      ) : null}
      {aiSource ? (
        <Suspense fallback={<p role="status" className="reader-error">正在加载阅读助手…</p>}>
          <ReaderAiPanel key={`${book.id}:${aiSource.locator}`} bookId={book.id} source={aiSource}
            settings={settings} onClose={() => setAiSource(null)} onSaved={async () => {
              await reloadMarks()
              void viewRef.current?.addAnnotation({ value: aiSource.locator, color: '#488bc2' })
            }}
            onGo={(target) => { goTo(target); setAiSource(null) }} />
        </Suspense>
      ) : null}
      {error ? <p className="reader-error">{error}</p> : null}
    </div>
  )
}
