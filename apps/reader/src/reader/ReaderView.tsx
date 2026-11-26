import { lazy, Suspense, useCallback, useEffect, useRef, useState } from 'react'
import { ChevronLeft, ChevronRight, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
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
import { applyReadingFont, applyViewLayout, highlightDraw, labelOf, themeOf, usesCapturedSlide } from './bookStyles'
import { loadBookSource, loadFoliate } from './bookSource'
import { cacheExcerptChapters, excerptChapter } from './excerptChapters'
import { normalizeSelectedText } from './selectionText'
import { mountReadingFont } from './fontLoader'
import { CapturedPageTurn } from './capturedTurn'
import { TurnQueue } from './turnQueue'
import { ReaderChrome } from './ReaderChrome'
import { ReaderFooter } from './ReaderFooter'
import { ReadingOverlays } from './ReadingOverlays'
import { ReaderSidebar, type SearchHit } from './ReaderSidebar'
import { classifyReadingTarget, resolveFootnoteText } from './readingTarget'
import { DEFAULT_HIGHLIGHT_COLOR, SelectionPopup, type SelectionState } from './SelectionPopup'
import { zoneOf } from './turnCommit'
import { bindReaderTouch, type BookmarkPull } from './readerTouch'
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

function selectionAtRange(frame: HTMLElement, range: Range, cfi: string, text: string): SelectionState | null {
  const rect = range.getBoundingClientRect()
  if (!rect.width || !rect.height) return null
  const frameRect = frame.getBoundingClientRect()
  const scaleX = frameRect.width / (frame.clientWidth || 1)
  const scaleY = frameRect.height / (frame.clientHeight || 1)
  return {
    text,
    cfi,
    x: frameRect.left + (rect.left + rect.width / 2) * scaleX,
    y: frameRect.top + rect.top * scaleY,
    bottom: frameRect.top + rect.bottom * scaleY,
  }
}

export function ReaderView({ book, onClose, initialLocator }: Props) {
  const hostRef = useRef<HTMLDivElement>(null)
  const viewRef = useRef<FoliateViewElement | null>(null)
  const excerptsRef = useRef<Excerpt[]>([])
  const marksRevision = useRef(0)
  const settingsRef = useRef<Settings>({})
  const saveTimer = useRef<number>(0)
  const prepareTimer = useRef<number>(0)
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
  const [currentToc, setCurrentToc] = useState<TocItem>()
  const [bookmarks, setBookmarks] = useState<Bookmark[]>([])
  const [excerpts, setExcerpts] = useState<Excerpt[]>([])
  const [settings, setSettings] = useState<Settings>({})
  const [selection, setSelection] = useState<SelectionState | null>(null)
  const selectionRef = useRef<SelectionState | null>(null)
  const savingExcerpt = useRef(false)
  const preferredHighlight = useRef(DEFAULT_HIGHLIGHT_COLOR)
  const savingBookmark = useRef(false)
  const addPageBookmarkRef = useRef<() => void>(() => undefined)
  const [bookmarkPull, setBookmarkPull] = useState<BookmarkPull | null>(null)
  const [aiSource, setAiSource] = useState<ReadingSource | null>(null)
  const [historyNav, setHistoryNav] = useState({ back: false, forward: false })
  const [location, setLocation] = useState<{ current: number; total: number } | null>(null)
  const [footnote, setFootnote] = useState<string | null>(null)
  const [picture, setPicture] = useState<{ src: string; alt: string } | null>(null)
  const [table, setTable] = useState<HTMLTableElement | null>(null)
  const [externalHref, setExternalHref] = useState<string | null>(null)
  const [searchSeed, setSearchSeed] = useState<{ id: number; query: string } | null>(null)
  const [searchNav, setSearchNav] = useState<{ hits: SearchHit[]; index: number } | null>(null)
  const searchNavRef = useRef(searchNav)
  searchNavRef.current = searchNav
  const mobile = isMobile()
  const chrome = useReaderChrome()
  const chromeRef = useRef(chrome)
  chromeRef.current = chrome
  const theme = themeOf(settings)
  const bookmarked = bookmarks.some((item) => item.locator === locator)
  const canBookmark = !status && !!locator

  const updateSelection = useCallback((next: SelectionState | null) => {
    selectionRef.current = next
    setSelection(next)
  }, [])

  const clearSelection = useCallback(() => {
    updateSelection(null)
    viewRef.current?.deselect()
  }, [updateSelection])

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
    const revision = ++marksRevision.current
    const previousExcerpts = excerptsRef.current
    const [nextBookmarks, nextExcerpts] = await Promise.all([
      api.listBookmarks(book.id),
      api.listExcerpts(book.id),
    ])
    if (revision !== marksRevision.current) return
    setBookmarks(nextBookmarks)
    if (excerptsRef.current !== previousExcerpts) return
    setExcerpts(nextExcerpts)
    excerptsRef.current = nextExcerpts
  }, [book.id])

  const paintHighlights = useCallback((view: FoliateViewElement) => {
    const painted = new Set<string>()
    for (const item of excerptsRef.current) {
      if (painted.has(item.locator)) continue
      painted.add(item.locator)
      void view.addAnnotation({ value: item.locator, color: item.color || DEFAULT_HIGHLIGHT_COLOR })
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
    if (selectionRef.current) clearSelection()
    turnQueue.current!.run(async () => {
      if (viewRef.current !== view) return
      const useCapture = usesCapturedSlide(settingsRef.current, isMobile())
      const started = useCapture && await getTurner().turn(forward)
      if (!started && viewRef.current === view) await (forward ? view.next() : view.prev())
      if (viewRef.current === view && useCapture) void getTurner().prepare()
    })
  }
  const turnRef = useRef(turn)
  turnRef.current = turn
  const keyRef = useRef<(event: KeyboardEvent) => void>(() => undefined)

  const goTo = (target: string) => {
    clearSelection()
    void viewRef.current?.goTo(target)
    chrome.closeSidebar()
  }

  const closeNavigation = () => {
    chrome.closeSidebar()
    if (mobile) chrome.hide()
  }

  const clearBookSearch = useCallback(() => {
    if (searchNavRef.current) return
    viewRef.current?.clearSearch()
  }, [])

  const searchBook = async (query: string, signal: AbortSignal) => {
    const view = viewRef.current
    const hits: SearchHit[] = []
    if (!view) return hits
    for await (const result of view.search({ query })) {
      if (signal.aborted || viewRef.current !== view) break
      if (result === 'done') break
      if ('subitems' in result) {
        for (const hit of result.subitems) {
          hits.push({ ...hit, chapter: result.label })
          if (hits.length >= 40) return hits
        }
      } else if ('cfi' in result) {
        hits.push(result)
        if (hits.length >= 40) break
      }
    }
    return hits
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
    void reloadMarks()
    const host = hostRef.current
    if (!host) return
    let cancelled = false
    let view: FoliateViewElement | null = null
    let ready = false
    let unlistenHistory: (() => void) | undefined
    const events = new AbortController()
    const { signal } = events
    const isPaginated = () => (settingsRef.current.flow ?? 'paginated') === 'paginated'
    const wheelState = createWheelTurnState()
    const onWheel = (event: WheelEvent) => {
      if (!isPaginated() || !viewRef.current || event.ctrlKey || event.metaKey) return
      if (event.deltaY === 0 || Math.abs(event.deltaY) <= Math.abs(event.deltaX)) return
      event.preventDefault()
      const direction = wheelTurnDirection(wheelState, event, host.clientHeight)
      if (direction !== null) turnRef.current(direction)
    }
    if (!mobile) host.addEventListener('wheel', onWheel, { signal, passive: false })

    const bindTouch = (target: Document | HTMLElement, selecting: () => boolean, frame?: HTMLElement) => {
      if (!mobile) return
      bindReaderTouch(target, {
        signal,
        host,
        frame,
        paginated: () => isPaginated() && !chromeRef.current.visible && !chromeRef.current.sidebar,
        selecting,
        captureTurns: () => usesCapturedSlide(settingsRef.current, mobile),
        prepareTurn: () => { void getTurner().prepare() },
        startTurn: (forward) => {
          if (turnQueue.current?.busy || selectionRef.current) return false
          const { page, pages } = view?.renderer ?? {}
          // A chapter turn replaces the iframe and ends its touch sequence.
          if (frame && (page == null || pages == null || (forward ? page >= pages - 2 : page <= 1))) return false
          return getTurner().startDrag(forward)
        },
        moveTurn: (progress) => getTurner().setProgress(progress),
        finishTurn: (forward, captured, commit) => {
          if (!captured) {
            if (commit && !selectionRef.current) turnRef.current(forward)
            return
          }
          const activeTurner = getTurner()
          turnQueue.current!.run(async () => {
            const started = await activeTurner.endDrag(commit)
            if (viewRef.current !== view || !view) return
            if (!started && commit) await (forward ? view.next() : view.prev())
            void activeTurner.prepare()
          })
        },
        canPullBookmark: () => !!view?.lastLocation?.cfi && !savingBookmark.current
          && !turnQueue.current?.busy && !selectionRef.current && (window.visualViewport?.scale ?? 1) <= 1,
        previewBookmark: setBookmarkPull,
        addBookmark: () => addPageBookmarkRef.current(),
        showChrome: () => chromeRef.current.toggle(),
      })
    }

    const handleTap = (event: MouseEvent, frame?: HTMLElement) => {
      if (event.button !== 0 || event.defaultPrevented) return
      if (selectionRef.current) {
        clearSelection()
        return
      }
      const ui = chromeRef.current
      if (ui.visible || ui.sidebar) {
        ui.hide()
        ui.closeSidebar()
        return
      }
      if ((event.target as Element | null)?.closest?.('a[href]')) return
      const bounds = host.getBoundingClientRect()
      const frameRect = frame?.getBoundingClientRect()
      const scale = frameRect && frame?.clientWidth ? frameRect.width / frame.clientWidth : 1
      const ratio = ((frameRect?.left ?? 0) + event.clientX * scale - bounds.left) / bounds.width
      const zone = zoneOf(ratio)
      if (zone === 'center' || !isPaginated()) ui.toggle()
      else turnRef.current(zone === 'right')
    }
    bindTouch(host, () => !!selectionRef.current)
    host.addEventListener('click', (event) => handleTap(event), { signal })

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
      const reader = view
      host.append(reader)
      viewRef.current = reader
      const syncHistory = () => {
        setHistoryNav({ back: reader.history.canGoBack, forward: reader.history.canGoForward })
      }
      reader.history.addEventListener('index-change', syncHistory)
      unlistenHistory = () => reader.history.removeEventListener('index-change', syncHistory)
      view.addEventListener('external-link', ((event: Event) => {
        event.preventDefault()
        const href = (event as CustomEvent<{ href_?: string }>).detail?.href_?.trim()
        if (href) setExternalHref(href)
      }) as EventListener)
      view.addEventListener('relocate', ((event: Event) => {
        setStatus('')
        const detail = (event as CustomEvent).detail as {
          cfi?: string
          fraction?: number
          tocItem?: TocItem
          location?: { current: number; total: number }
        }
        const fraction = Number(detail.fraction ?? 0)
        const place = detail.location
        setLocation(place && place.total > 0 ? { current: place.current, total: place.total } : null)
        setProgress(fraction)
        const chapterTitle = labelOf(detail.tocItem?.label)
        setCurrentToc(detail.tocItem)
        setChapter(chapterTitle)
        setLocator(detail.cfi ?? '')
        void api.saveProgress(book.id, detail.cfi ?? '', fraction, chapterTitle || undefined)
        getTurner().invalidate()
        window.clearTimeout(prepareTimer.current)
        if (usesCapturedSlide(settingsRef.current, mobile)) {
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
        detail.draw(highlightDraw, { color: detail.annotation.color ?? DEFAULT_HIGHLIGHT_COLOR })
      }) as EventListener)
      view.addEventListener('create-overlay', (() => {
        if (view) paintHighlights(view)
      }) as EventListener)
      view.addEventListener('load', ((event: Event) => {
        const detail = (event as CustomEvent).detail as { doc?: Document; index?: number }
        const doc = detail.doc
        const currentView = view
        const frame = doc?.defaultView?.frameElement as HTMLElement | null
        if (!doc || !currentView || !frame) return
        updateSelection(null)
        void applyReadingFont(currentView, settingsRef.current)
        const index = detail.index ?? 0
        let mouseSelecting = false
        let pressedWhileSelected = false
        const hasNativeSelection = () => !!doc.getSelection()?.toString().trim()
        const readSelection = () => {
          if (!frame.isConnected || mouseSelecting) return
          const native = doc.getSelection()
          const text = normalizeSelectedText(native?.toString() ?? '')
          if (!native?.rangeCount || !text) {
            // Keep the quote when a toolbar action moves focus out of the iframe.
            if (pressedWhileSelected) updateSelection(null)
            return
          }
          pressedWhileSelected = false
          const range = native.getRangeAt(0)
          const anchor = selectionAtRange(frame, range, currentView.getCFI(index, range), text)
          if (anchor) {
            const { tocItem } = currentView.getProgressOf(index, range)
            updateSelection({ ...anchor, chapter: excerptChapter(tocItem) })
          }
        }
        doc.addEventListener('selectionchange', readSelection, { signal })
        if (mobile) doc.addEventListener('contextmenu', (event) => {
          if (hasNativeSelection()) event.preventDefault()
        }, { signal, capture: true })
        doc.addEventListener('pointerdown', (event) => {
          mouseSelecting = event.pointerType === 'mouse'
          pressedWhileSelected = hasNativeSelection()
        }, { signal })
        doc.addEventListener('pointercancel', () => {
          mouseSelecting = false
          pressedWhileSelected = false
        }, { signal })
        doc.addEventListener('mouseup', () => {
          mouseSelecting = false
          if (hasNativeSelection()) readSelection()
        }, { signal })
        doc.addEventListener('keydown', (event) => keyRef.current(event), { signal })
        if (!mobile) doc.addEventListener('wheel', onWheel, { signal, passive: false })
        bindTouch(doc, hasNativeSelection, frame)
        doc.addEventListener('click', (event) => {
          const hasSelection = hasNativeSelection()
          if (hasSelection || pressedWhileSelected) {
            if (!hasSelection) {
              pressedWhileSelected = false
              clearSelection()
            }
            event.preventDefault()
            event.stopImmediatePropagation()
            return
          }
          const targetNode = event.target as Node | null
          const element = targetNode?.nodeType === Node.ELEMENT_NODE ? targetNode as Element : null
          const readingTarget = element ? classifyReadingTarget(element) : null
          if (readingTarget?.kind === 'footnote') {
            const text = resolveFootnoteText(readingTarget.inline, readingTarget.hash, (id) => doc.getElementById(id)?.textContent ?? null)
            if (text) {
              event.preventDefault()
              event.stopImmediatePropagation()
              setFootnote(text)
              return
            }
          }
          if (readingTarget?.kind === 'image' && element) {
            const image = element.closest('img') as HTMLImageElement | null
            const src = image?.src || readingTarget.src
            if (src) {
              event.preventDefault()
              event.stopImmediatePropagation()
              setPicture({ src, alt: readingTarget.alt })
              return
            }
          }
          if (readingTarget?.kind === 'table' && element) {
            const source = element.closest('table')
            if (source) {
              event.preventDefault()
              event.stopImmediatePropagation()
              setTable(document.importNode(source, true) as HTMLTableElement)
              return
            }
          }
          if (event.button === 0 && !event.defaultPrevented) {
            const content = currentView.renderer.getContents?.().find((item) => item.doc === doc)
            const hit = content?.overlayer?.hitTest(event)
            const excerpt = hit?.length && excerptsRef.current.find((item) => item.locator === hit[0])
            if (hit?.length && excerpt) {
              const anchor = selectionAtRange(frame, hit[1], excerpt.locator, excerpt.quote)
              if (anchor) {
                chromeRef.current.hide()
                const { tocItem } = currentView.getProgressOf(index, hit[1])
                updateSelection({ ...anchor, chapter: excerpt.chapter ?? excerptChapter(tocItem) })
                event.preventDefault()
                event.stopImmediatePropagation()
                return
              }
            }
          }
          handleTap(event, frame)
        }, { signal, capture: true })
        paintHighlights(currentView)
      }) as EventListener)
      await view.open(source)
      if (cancelled) return
      if (loaded.edgeEverEnabled) {
        void api.listExcerpts(book.id)
          .then((items) => { if (!cancelled) return cacheExcerptChapters(reader, book.id, items) })
          .catch(console.warn)
      }
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
      unlistenHistory?.()
      events.abort()
      window.clearTimeout(prepareTimer.current)
      window.clearTimeout(saveTimer.current)
      turnQueue.current?.clear()
      updateSelection(null)
      setBookmarkPull(null)
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
  }, [book.id, initialLocator, clearSelection, updateSelection])

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

  keyRef.current = (event: KeyboardEvent) => {
    if (chrome.sidebar || event.defaultPrevented) return
    const target = event.target as HTMLElement | null
    if (target?.closest?.('button, input, textarea, select') || target?.isContentEditable) {
      return
    }
    if (event.key === 'Escape') {
      if (selectionRef.current) {
        clearSelection()
        return
      }
      if (chrome.visible) {
        chrome.hide()
        return
      }
      onClose()
      return
    }
    if (event.shiftKey || event.ctrlKey || event.metaKey || event.altKey) return
    if (event.key === 'ArrowLeft' || event.key === 'PageUp') {
      event.preventDefault()
      turn(false)
    }
    if (event.key === 'ArrowRight' || event.key === 'PageDown' || event.key === ' ') {
      event.preventDefault()
      turn(true)
    }
  }
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => keyRef.current(event)
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  const saveExcerpt = async (selected: SelectionState, color: string, note?: string) => {
    if (savingExcerpt.current) return false
    savingExcerpt.current = true
    const view = viewRef.current
    try {
      const existing = excerptsRef.current.find((item) => item.locator === selected.cfi)
      const savedNote = note === undefined ? existing?.note ?? undefined : note || undefined
      let saved: Excerpt
      if (existing) {
        if (!existing.chapter && selected.chapter) {
          await api.cacheExcerptChapters(book.id, [[selected.cfi, selected.chapter]])
        }
        await api.updateExcerpt({ id: existing.id, quote: existing.quote, note: savedNote, color })
        saved = { ...existing, note: savedNote, color, chapter: existing.chapter ?? selected.chapter }
      } else {
        const input = { bookId: book.id, locator: selected.cfi, quote: selected.text, note: savedNote, color, chapter: selected.chapter }
        const id = await api.createExcerpt(input)
        saved = { ...input, id, createdAt: new Date().toISOString() }
      }
      if (viewRef.current !== view) return true
      const next = [saved, ...excerptsRef.current.filter((item) => item.id !== saved.id)]
      excerptsRef.current = next
      setExcerpts(next)
      if (selectionRef.current?.cfi === selected.cfi) view?.deselect()
      void view?.addAnnotation({ value: selected.cfi, color }).catch(console.error)
      if (!existing) toast.success('书摘已保存')
      return true
    } catch {
      toast.error('书摘保存失败，请重试')
      return false
    } finally {
      savingExcerpt.current = false
    }
  }

  const removeExcerpt = async (excerpt: Excerpt) => {
    if (savingExcerpt.current) return
    savingExcerpt.current = true
    const view = viewRef.current
    try {
      await api.deleteExcerpt(excerpt.id)
      if (viewRef.current !== view) return
      const remaining = excerptsRef.current.filter((item) => item.id !== excerpt.id)
      excerptsRef.current = remaining
      setExcerpts(remaining)
      if (selectionRef.current?.cfi === excerpt.locator) clearSelection()
      const previous = remaining.find((item) => item.locator === excerpt.locator)
      if (previous) await view?.addAnnotation({ value: previous.locator, color: previous.color })
      else await view?.deleteAnnotation({ value: excerpt.locator })
    } catch {
      toast.error('书摘移除失败，请重试')
    } finally {
      savingExcerpt.current = false
    }
  }

  const saveBookmark = async (operation: () => Promise<unknown>) => {
    if (savingBookmark.current) return
    savingBookmark.current = true
    try {
      await operation()
      await reloadMarks()
    } catch {
      toast.error('书签更新失败，请重试')
    } finally {
      savingBookmark.current = false
    }
  }

  const stepHistory = (forward: boolean) => {
    const history = viewRef.current?.history
    if (!history) return
    clearSelection()
    if (forward) history.forward()
    else history.back()
    chrome.hide()
  }

  const turnSection = (forward: boolean) => {
    const renderer = viewRef.current?.renderer
    if (!renderer) return
    clearSelection()
    chrome.hide()
    void (forward ? renderer.nextSection?.() : renderer.prevSection?.())
  }

  const goToLocation = (page: number) => {
    const total = location?.total
    if (!total || page < 1 || page > total) return
    clearSelection()
    void viewRef.current?.goToFraction(Math.min(0.999, (page - 1) / total))
  }

  const showSearchHit = (index: number) => {
    const current = searchNavRef.current
    const hit = current?.hits[index]
    if (!current || !hit) return
    const next = { hits: current.hits, index }
    searchNavRef.current = next
    setSearchNav(next)
    goTo(hit.cfi)
  }

  const toggleBookmark = () => {
    const current = viewRef.current?.lastLocation?.cfi ?? locator
    if (!current || !canBookmark) return
    const existing = bookmarks.find((item) => item.locator === current)
    void saveBookmark(() => existing
      ? api.deleteBookmark(existing.id)
      : api.addBookmark(book.id, current, chapter || title))
  }

  addPageBookmarkRef.current = () => {
    const current = viewRef.current?.lastLocation?.cfi
    if (!current || !canBookmark || bookmarks.some((item) => item.locator === current)) return
    void saveBookmark(async () => {
      const currentBookmarks = await api.listBookmarks(book.id)
      if (currentBookmarks.some((item) => item.locator === current)) return
      await api.addBookmark(book.id, current, chapter || title)
    })
  }

  const selectedExcerpt = selection ? excerpts.find((item) => item.locator === selection.cfi) : undefined

  return (
    <div
      className={mobile ? 'reader-shell is-mobile' : 'reader-shell'}
      style={{ color: theme.fg, background: theme.bg }}
    >
      <div className="reader-stage outline-none" ref={hostRef} tabIndex={-1}>
        {status ? <p className="reader-status">{status}</p> : null}
      </div>

      <ReaderChrome
        title={title}
        chapter={chapter}
        progress={progress}
        visible={chrome.visible}
        bookmarked={bookmarked}
        bookmarkPull={bookmarkPull}
        canBookmark={canBookmark}
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
        canGoBack={historyNav.back}
        canGoForward={historyNav.forward}
        locationCurrent={location ? location.current + 1 : null}
        locationTotal={location?.total ?? null}
        onOpenTab={chrome.openTab}
        onPatch={patchSettings}
        onGoToFraction={(value) => {
          clearSelection()
          void viewRef.current?.goToFraction(value)
        }}
        onGoToLocation={goToLocation}
        onHistory={stepHistory}
        onSection={turnSection}
        onTurn={turn}
        onKeepVisible={chrome.show}
        onRequestHide={chrome.hide}
      />
      <ReaderSidebar
        open={chrome.sidebar}
        mobile={mobile}
        title={title}
        author={book.author}
        toc={toc}
        currentToc={currentToc}
        locator={locator}
        progress={progress}
        bookmarks={bookmarks}
        excerpts={excerpts}
        settings={settings}
        canBookmark={canBookmark}
        onPatch={patchSettings}
        onSearch={searchBook}
        onClearSearch={clearBookSearch}
        searchSeed={searchSeed}
        onPickSearch={(hits, index) => {
          const next = { hits, index }
          searchNavRef.current = next
          setSearchNav(next)
          goTo(hits[index]?.cfi ?? '')
          if (mobile) chrome.hide()
        }}
        onGo={(target) => {
          goTo(target)
          if (mobile) chrome.hide()
        }}
        onAddBookmark={toggleBookmark}
        onDeleteBookmark={(id) => void saveBookmark(() => api.deleteBookmark(id))}
        onClose={closeNavigation}
        onRestoreFocus={() => hostRef.current?.focus({ preventScroll: true })}
      />
      {selection ? (
        <SelectionPopup
          key={selection.cfi}
          selection={selection}
          excerpt={selectedExcerpt}
          defaultColor={preferredHighlight.current}
          mobile={mobile}
          onAiExplain={() => {
            if (selection.text.length > 16_000) {
              toast.error('选中文字过长，请缩小到 16,000 字以内再提问')
              return
            }
            setAiSource({
              bookTitle: title,
              chapter: selection.chapter?.title || chapter,
              excerptChapter: selection.chapter,
              quote: selection.text,
              locator: selection.cfi,
            })
            clearSelection()
            chrome.hide()
          }}
          onCopy={() => {
            void navigator.clipboard.writeText(selection.text)
            clearSelection()
          }}
          onColor={async (color) => {
            const saved = await saveExcerpt(selection, color)
            if (saved) preferredHighlight.current = color
            return saved
          }}
          onOpenNote={() => viewRef.current?.deselect()}
          onSaveNote={(note) => saveExcerpt(selection, selectedExcerpt?.color || preferredHighlight.current, note)}
          onRemove={async () => {
            if (selectedExcerpt) await removeExcerpt(selectedExcerpt)
          }}
          onDismiss={() => {
            if (selectionRef.current?.cfi === selection.cfi) clearSelection()
          }}
          onBookmark={() => {
            void api.addBookmark(book.id, selection.cfi, selection.text.slice(0, 40)).then(() => {
              void reloadMarks()
              if (selectionRef.current?.cfi === selection.cfi) clearSelection()
            })
          }}
          onSearch={() => {
            const query = selection.text.replace(/\s+/g, ' ').trim().slice(0, 80)
            if (!query) return
            setSearchSeed({ id: Date.now(), query })
            chrome.openSidebar()
            clearSelection()
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
      {searchNav && !chrome.sidebar ? (
        <div className="reader-search-nav" role="navigation" aria-label="搜索结果">
          <Button type="button" variant="ghost" size="icon-sm" aria-label="上一处" disabled={searchNav.index <= 0} onClick={() => showSearchHit(searchNav.index - 1)}>
            <ChevronLeft />
          </Button>
          <span className="text-xs tabular-nums">{searchNav.index + 1} / {searchNav.hits.length}</span>
          <Button type="button" variant="ghost" size="icon-sm" aria-label="下一处" disabled={searchNav.index >= searchNav.hits.length - 1} onClick={() => showSearchHit(searchNav.index + 1)}>
            <ChevronRight />
          </Button>
          <Button type="button" variant="ghost" size="icon-sm" aria-label="关闭搜索" onClick={() => {
            searchNavRef.current = null
            setSearchNav(null)
            viewRef.current?.clearSearch()
          }}>
            <X />
          </Button>
        </div>
      ) : null}
      <ReadingOverlays
        footnote={footnote}
        picture={picture}
        table={table}
        externalHref={externalHref}
        onCloseFootnote={() => setFootnote(null)}
        onClosePicture={() => setPicture(null)}
        onCloseTable={() => setTable(null)}
        onCloseExternal={() => setExternalHref(null)}
        onOpenExternal={() => {
          if (externalHref) window.open(externalHref, '_blank', 'noopener,noreferrer')
          setExternalHref(null)
        }}
      />
      {error ? <p className="reader-error">{error}</p> : null}
    </div>
  )
}
