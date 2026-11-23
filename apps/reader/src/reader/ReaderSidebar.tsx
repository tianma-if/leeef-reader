import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { Bookmark as BookmarkIcon, ChevronDown, ChevronLeft, ChevronRight, List, NotebookPen, Search, Trash2, X } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Sheet, SheetContent, SheetTitle } from '@/components/ui/sheet'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Slider } from '@/components/ui/slider'
import type { Bookmark, Excerpt, Settings } from '../api'
import { THEMES, labelOf, type ThemeName } from './bookStyles'
import { FontPicker } from './FontPicker'

type SidebarTab = 'toc' | 'excerpts' | 'bookmarks' | 'style'
export type SearchHit = { cfi: string; excerpt: FoliateSearchExcerpt; chapter?: string }

type Props = {
  open: boolean
  mobile: boolean
  title: string
  author?: string | null
  toc: TocItem[]
  currentToc?: TocItem
  locator: string
  progress: number
  bookmarks: Bookmark[]
  excerpts: Excerpt[]
  settings: Settings
  canBookmark: boolean
  onPatch: (partial: Partial<Settings>) => void
  onSearch: (query: string, signal: AbortSignal) => Promise<SearchHit[]>
  onClearSearch: () => void
  searchSeed?: { id: number; query: string } | null
  onPickSearch?: (hits: SearchHit[], index: number) => void
  onGo: (locator: string) => void
  onAddBookmark: () => void
  onDeleteBookmark: (id: string) => void
  onClose: () => void
  onRestoreFocus: () => void
}

const navigationTabs = [
  { value: 'toc', label: '目录', Icon: List },
  { value: 'excerpts', label: '书摘', Icon: NotebookPen },
  { value: 'bookmarks', label: '书签', Icon: BookmarkIcon },
] as const

function currentPath(items: TocItem[], current: TocItem | undefined): TocItem[] {
  if (!current) return []
  for (const item of items) {
    if (item === current || (item.id !== undefined && item.id === current.id)) return [item]
    const children = currentPath(item.subitems ?? [], current)
    if (children.length) return [item, ...children]
  }
  return []
}

function TocList({ toc, currentToc, locator, progress, onGo }: Pick<Props, 'toc' | 'currentToc' | 'locator' | 'progress' | 'onGo'>) {
  const [expanded, setExpanded] = useState(() => {
    const ancestors = currentPath(toc, currentToc).slice(0, -1)
    const root = toc[0]
    if (!ancestors.length && toc.length === 1 && root?.subitems?.length) ancestors.push(root)
    return new Set(ancestors)
  })
  const activeRow = useRef<HTMLButtonElement>(null)

  useLayoutEffect(() => {
    activeRow.current?.scrollIntoView({ block: 'center' })
  }, [toc, currentToc])

  const toggle = (item: TocItem) => {
    setExpanded((previous) => {
      const next = new Set(previous)
      if (!next.delete(item)) next.add(item)
      return next
    })
  }

  const renderItems = (items: TocItem[], depth = 0) => (
    <ul>
      {items.map((item, index) => {
        const label = labelOf(item.label) || item.href || '未命名章节'
        const hasChildren = Boolean(item.subitems?.length)
        const isExpanded = expanded.has(item)
        const indent = Math.min(depth, 6) * 14
        const active = Boolean(currentToc && (item === currentToc || (item.id !== undefined && item.id === currentToc.id)))
        return (
          <li key={item.id ?? index}>
            <div className="reader-toc-row" data-current={active} style={{ paddingInlineStart: indent }}>
              <button
                ref={active ? activeRow : undefined}
                type="button"
                className="reader-list-link"
                aria-current={active ? 'location' : undefined}
                disabled={!item.href && !hasChildren}
                onClick={() => item.href ? onGo(item.href) : toggle(item)}
              >
                {label}
              </button>
              {hasChildren ? (
                <Button
                  type="button"
                  variant="ghost"
                  className="reader-nav-icon"
                  aria-expanded={isExpanded}
                  aria-label={`${isExpanded ? '收起' : '展开'}${label}`}
                  onClick={() => toggle(item)}
                >
                  {isExpanded ? <ChevronDown /> : <ChevronRight />}
                </Button>
              ) : null}
            </div>
            {active && locator ? (
              <button
                type="button"
                className="reader-current-position"
                style={{ marginInlineStart: indent + 12 }}
                onClick={() => onGo(locator)}
              >
                当前阅读位置 · {(progress * 100).toFixed(1)}%
              </button>
            ) : null}
            {isExpanded && item.subitems?.length ? renderItems(item.subitems, depth + 1) : null}
          </li>
        )
      })}
    </ul>
  )

  return toc.length ? renderItems(toc) : <p className="reader-nav-empty">这本书没有目录</p>
}

function SearchResults({ hits, searching, onGo, onPick }: { hits: SearchHit[] | null; searching: boolean; onGo: Props['onGo']; onPick?: Props['onPickSearch'] }) {
  if (searching) return <p role="status" className="reader-nav-empty">正在搜索…</p>
  if (!hits) return null
  if (!hits.length) return <p role="status" className="reader-nav-empty">未找到匹配内容</p>
  return (
    <ul className="reader-mark-list">
      {hits.map(({ cfi, excerpt, chapter }, index) => (
        <li className="reader-mark-row" key={cfi}>
          <button type="button" className="reader-list-link" onClick={() => onPick ? onPick(hits, index) : onGo(cfi)}>
            {chapter ? <span className="reader-mark-note">{chapter}</span> : null}
            <span>{excerpt.pre}<mark>{excerpt.match}</mark>{excerpt.post}</span>
          </button>
        </li>
      ))}
    </ul>
  )
}

function ReaderSidebarBody(props: Props) {
  const { onClearSearch } = props
  const [tab, setTab] = useState<SidebarTab>('toc')
  const [searchOpen, setSearchOpen] = useState(false)
  const [query, setQuery] = useState('')
  const [hits, setHits] = useState<SearchHit[] | null>(null)
  const [searching, setSearching] = useState(false)
  const searchRequest = useRef<AbortController | null>(null)
  const searchInput = useRef<HTMLInputElement>(null)
  const searchInBook = searchOpen && (tab === 'toc' || tab === 'bookmarks')
  const searchExcerpts = searchOpen && tab === 'excerpts'
  const term = query.trim().toLowerCase()
  const shownExcerpts = searchExcerpts && term
    ? props.excerpts.filter((item) => item.quote.toLowerCase().includes(term) || item.note?.toLowerCase().includes(term))
    : props.excerpts

  useEffect(() => () => {
    if (!searchRequest.current) return
    searchRequest.current.abort()
    onClearSearch()
  }, [onClearSearch])

  useEffect(() => {
    if (searchOpen) searchInput.current?.focus()
  }, [searchOpen])

  useEffect(() => {
    const seed = props.searchSeed
    if (!seed) return
    searchRequest.current?.abort()
    const request = new AbortController()
    searchRequest.current = request
    setTab('toc')
    setSearchOpen(true)
    setQuery(seed.query)
    setHits(null)
    setSearching(true)
    void props.onSearch(seed.query, request.signal).then((results) => {
      if (!request.signal.aborted) setHits(results)
    }).catch(() => {
      if (!request.signal.aborted) {
        setHits(null)
        toast.error('搜索失败，请重试')
      }
    }).finally(() => {
      if (!request.signal.aborted) setSearching(false)
    })
    return () => request.abort()
  }, [props.searchSeed])

  const closeSearch = () => {
    searchRequest.current?.abort()
    searchRequest.current = null
    if (searchInBook) onClearSearch()
    setSearchOpen(false)
    setQuery('')
    setHits(null)
    setSearching(false)
  }

  const changeTab = (value: string) => {
    closeSearch()
    setTab(value as SidebarTab)
  }

  const searchBook = async () => {
    if (!term) return
    searchRequest.current?.abort()
    const request = new AbortController()
    searchRequest.current = request
    setSearching(true)
    try {
      const results = await props.onSearch(query.trim(), request.signal)
      if (!request.signal.aborted) setHits(results)
    } catch {
      if (!request.signal.aborted) {
        setHits(null)
        toast.error('搜索失败，请重试')
      }
    } finally {
      if (!request.signal.aborted) setSearching(false)
    }
  }

  return (
    <>
      <header className="reader-nav-header">
        <Button type="button" variant="ghost" className="reader-nav-icon" aria-label="返回阅读" data-reader-nav-close onClick={props.onClose}>
          <ChevronLeft />
        </Button>
        <div className="reader-nav-book">
          <strong>{props.title}</strong>
          {props.author ? <span>{props.author}</span> : null}
        </div>
        <Button
          type="button"
          variant="ghost"
          className={tab === 'style' ? 'reader-nav-icon invisible' : 'reader-nav-icon'}
          aria-label={searchOpen ? '关闭搜索' : tab === 'excerpts' ? '搜索书摘' : '书内搜索'}
          aria-expanded={searchOpen}
          onClick={() => searchOpen ? closeSearch() : setSearchOpen(true)}
        >
          {searchOpen ? <X /> : <Search />}
        </Button>
      </header>
      {searchOpen ? (
        <form className="reader-nav-search" onSubmit={(event) => {
          event.preventDefault()
          if (searchInBook) void searchBook()
        }}>
          <Input
            ref={searchInput}
            aria-label={searchExcerpts ? '搜索书摘' : '书内搜索'}
            placeholder={searchExcerpts ? '搜索原文或笔记' : '搜索书内文字'}
            type="search"
            enterKeyHint="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
          />
          {searchInBook ? <Button type="submit" variant="secondary" disabled={!term}>搜索</Button> : null}
        </form>
      ) : null}
      <Tabs value={tab} onValueChange={changeTab} activationMode="manual" className="reader-nav-tabs">
        <TabsContent value="toc" className="reader-nav-scroll">
          {searchInBook ? <SearchResults hits={hits} searching={searching} onGo={props.onGo} onPick={props.onPickSearch} /> : (
            <TocList
              key={props.currentToc?.id ?? props.currentToc?.href}
              toc={props.toc}
              currentToc={props.currentToc}
              locator={props.locator}
              progress={props.progress}
              onGo={props.onGo}
            />
          )}
        </TabsContent>
        <TabsContent value="excerpts" className="reader-nav-scroll">
          {shownExcerpts.length ? (
            <ul className="reader-mark-list">
              {shownExcerpts.map((item) => (
                <li key={item.id} className="reader-mark-row">
                  <button type="button" className="reader-list-link" onClick={() => props.onGo(item.locator)}>
                    <span className="reader-excerpt-quote" style={{ borderInlineStartColor: item.color || undefined }}>{item.quote}</span>
                    {item.note ? <span className="reader-mark-note">{item.note}</span> : null}
                  </button>
                </li>
              ))}
            </ul>
          ) : <p className="reader-nav-empty">{term ? '未找到匹配的书摘' : '还没有书摘，选中文字后点「存书摘」'}</p>}
        </TabsContent>
        <TabsContent value="bookmarks" className="reader-nav-scroll">
          {searchInBook ? <SearchResults hits={hits} searching={searching} onGo={props.onGo} onPick={props.onPickSearch} /> : props.bookmarks.length ? (
            <ul className="reader-mark-list">
              {props.bookmarks.map((item) => {
                const label = item.title?.trim() || '未命名书签'
                return (
                  <li key={item.id} className="reader-mark-row" data-current={item.locator === props.locator}>
                    <button type="button" className="reader-list-link" onClick={() => props.onGo(item.locator)}>
                      <span>{label}</span>
                      {item.note ? <span className="reader-mark-note">{item.note}</span> : null}
                    </button>
                    <Button
                      type="button"
                      variant="ghost"
                      className="reader-nav-icon reader-mark-delete"
                      aria-label={`删除书签：${label}`}
                      onClick={() => props.onDeleteBookmark(item.id)}
                    >
                      <Trash2 />
                    </Button>
                  </li>
                )
              })}
            </ul>
          ) : (
            <div className="reader-nav-empty">
              <p>还没有书签</p>
              <Button type="button" variant="outline" disabled={!props.canBookmark} onClick={props.onAddBookmark}>
                <BookmarkIcon /> 为当前页添加书签
              </Button>
            </div>
          )}
        </TabsContent>
        {!props.mobile ? (
          <TabsContent value="style" className="reader-nav-scroll">
            <div className="grid gap-4 px-2 py-2">
              <FontPicker
                value={props.settings.fontFamily}
                onChange={(fontFamily) => props.onPatch({ fontFamily })}
              />
              <div className="flex flex-wrap gap-2">
                {(Object.keys(THEMES) as ThemeName[]).map((name) => (
                  <Button
                    key={name}
                    type="button"
                    size="sm"
                    variant={(props.settings.theme ?? 'paper') === name ? 'default' : 'outline'}
                    onClick={() => props.onPatch({ theme: name })}
                  >
                    {THEMES[name].name}
                  </Button>
                ))}
              </div>
              <label className="grid gap-2 text-sm">
                字号 {props.settings.fontSize ?? 18}
                <Slider
                  min={14}
                  max={28}
                  value={[props.settings.fontSize ?? 18]}
                  onValueChange={([value]) => props.onPatch({ fontSize: value })}
                />
              </label>
              <label className="grid gap-2 text-sm">
                行距 {(props.settings.lineHeight ?? 1.65).toFixed(2)}
                <Slider
                  min={1.3}
                  max={2.2}
                  step={0.05}
                  value={[props.settings.lineHeight ?? 1.65]}
                  onValueChange={([value]) => props.onPatch({ lineHeight: value })}
                />
              </label>
              <div className="flex flex-wrap gap-2">
                <Button
                  type="button"
                  size="sm"
                  variant={(props.settings.flow ?? 'paginated') === 'paginated' ? 'default' : 'outline'}
                  onClick={() => props.onPatch({ flow: 'paginated' })}
                >
                  分页
                </Button>
                <Button
                  type="button"
                  size="sm"
                  variant={props.settings.flow === 'scrolled' ? 'default' : 'outline'}
                  onClick={() => props.onPatch({ flow: 'scrolled' })}
                >
                  滚动
                </Button>
                <Button
                  type="button"
                  size="sm"
                  variant={(props.settings.columns ?? 1) === 1 ? 'default' : 'outline'}
                  onClick={() => props.onPatch({ columns: 1 })}
                >
                  单栏
                </Button>
                <Button
                  type="button"
                  size="sm"
                  variant={props.settings.columns === 2 ? 'default' : 'outline'}
                  onClick={() => props.onPatch({ columns: 2 })}
                >
                  双栏
                </Button>
              </div>
            </div>
          </TabsContent>
        ) : null}
        <TabsList className="reader-nav-tabs-list" aria-label="阅读导航">
          {navigationTabs.map(({ value, label, Icon }) => (
            <TabsTrigger
              key={value}
              value={value}
              onMouseDown={(event) => {
                if (props.mobile && value === tab && event.button === 0 && !event.ctrlKey) props.onClose()
              }}
              onKeyDown={(event) => {
                if (props.mobile && value === tab && (event.key === 'Enter' || event.key === ' ')) props.onClose()
              }}
            >
              <Icon />
              {label}
            </TabsTrigger>
          ))}
          {!props.mobile ? <TabsTrigger value="style">样式</TabsTrigger> : null}
        </TabsList>
      </Tabs>
    </>
  )
}

export function ReaderSidebar(props: Props) {
  const dragStart = useRef<number | null>(null)
  const [dragOffset, setDragOffset] = useState(0)

  return (
    <Sheet open={props.open} onOpenChange={(open) => !open && props.onClose()}>
      <SheetContent
        side={props.mobile ? 'bottom' : 'right'}
        className={props.mobile ? 'reader-nav-sheet reader-nav-sheet-mobile' : 'reader-nav-sheet'}
        style={{ translate: dragOffset ? `0 ${dragOffset}px` : undefined }}
        showCloseButton={false}
        aria-describedby={undefined}
        onOpenAutoFocus={(event) => {
          const closeButton = (event.currentTarget as HTMLElement | null)?.querySelector<HTMLButtonElement>('[data-reader-nav-close]')
          if (!closeButton) return
          event.preventDefault()
          closeButton.focus()
        }}
        onCloseAutoFocus={(event) => {
          event.preventDefault()
          props.onRestoreFocus()
        }}
      >
        <SheetTitle className="sr-only">目录、书摘与书签</SheetTitle>
        {props.mobile ? (
          <div
            className="reader-nav-grip"
            aria-hidden="true"
            onPointerDown={(event) => {
              if (!event.isPrimary || event.button !== 0) return
              dragStart.current = event.clientY
              event.currentTarget.setPointerCapture(event.pointerId)
            }}
            onPointerMove={(event) => {
              if (!event.isPrimary || dragStart.current === null) return
              setDragOffset(Math.max(0, event.clientY - dragStart.current))
            }}
            onPointerUp={(event) => {
              if (!event.isPrimary || dragStart.current === null) return
              const distance = event.clientY - dragStart.current
              dragStart.current = null
              setDragOffset(0)
              if (distance >= Math.min(140, window.innerHeight * 0.24)) props.onClose()
            }}
            onLostPointerCapture={() => {
              dragStart.current = null
              setDragOffset(0)
            }}
          ><span /></div>
        ) : null}
        <ReaderSidebarBody {...props} />
      </SheetContent>
    </Sheet>
  )
}
