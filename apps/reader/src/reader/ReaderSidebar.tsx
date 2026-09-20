import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { ScrollArea } from '@/components/ui/scroll-area'
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from '@/components/ui/sheet'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Slider } from '@/components/ui/slider'
import type { Bookmark, Excerpt, Settings } from '../api'
import { THEMES, labelOf, type ThemeName } from './bookStyles'
import { FontPicker } from './FontPicker'

type Props = {
  open: boolean
  mobile: boolean
  toc: TocItem[]
  query: string
  hits: { cfi?: string; excerpt?: string }[]
  bookmarks: Bookmark[]
  excerpts: Excerpt[]
  settings: Settings
  onPatch: (partial: Partial<Settings>) => void
  onQuery: (value: string) => void
  onSearch: () => void
  onGo: (locator: string) => void
  onAddBookmark: () => void
  onDeleteBookmark: (id: string) => void
  onClose: () => void
}

function TocTree({
  items,
  depth = 0,
  onGo,
}: {
  items: TocItem[]
  depth?: number
  onGo: (locator: string) => void
}) {
  return (
    <div>
      {items.map((item, index) => (
        <div key={`${item.href ?? item.label}-${index}`}>
          <button
            type="button"
            className="hover:bg-muted w-full truncate rounded-md px-2 py-1.5 text-left text-sm"
            style={{ paddingLeft: `${0.5 + depth * 0.75}rem` }}
            onClick={() => item.href && onGo(item.href)}
          >
            {labelOf(item.label) || item.href}
          </button>
          {item.subitems?.length ? (
            <TocTree items={item.subitems} depth={depth + 1} onGo={onGo} />
          ) : null}
        </div>
      ))}
    </div>
  )
}

function SidebarBody(props: Omit<Props, 'open' | 'onClose'> & { mobile: boolean }) {
  return (
    <Tabs defaultValue="toc" className="min-h-0 flex-1">
      <TabsList className="mx-3">
        <TabsTrigger value="toc">目录</TabsTrigger>
        <TabsTrigger value="search">搜索</TabsTrigger>
        <TabsTrigger value="marks">书签</TabsTrigger>
        {!props.mobile ? <TabsTrigger value="style">样式</TabsTrigger> : null}
      </TabsList>
      <TabsContent value="toc" className="min-h-0 flex-1">
        <ScrollArea className="h-[min(60vh,28rem)] px-2">
          {props.toc.length ? (
            <TocTree items={props.toc} onGo={props.onGo} />
          ) : (
            <p className="text-muted-foreground px-3 py-4 text-sm">没有目录。</p>
          )}
        </ScrollArea>
      </TabsContent>
      <TabsContent value="search" className="grid gap-2 px-3">
        <Input
          value={props.query}
          onChange={(event) => props.onQuery(event.target.value)}
          placeholder="书内搜索"
          onKeyDown={(event) => {
            if (event.key === 'Enter') props.onSearch()
          }}
        />
        <ScrollArea className="h-[min(48vh,22rem)]">
          {props.hits.map((hit) => (
            <button
              key={hit.cfi}
              type="button"
              className="hover:bg-muted block w-full truncate rounded-md px-2 py-1.5 text-left text-sm"
              onClick={() => hit.cfi && props.onGo(hit.cfi)}
            >
              {hit.excerpt}
            </button>
          ))}
        </ScrollArea>
      </TabsContent>
      <TabsContent value="marks" className="grid gap-2 px-3">
        <Button type="button" size="sm" variant="outline" onClick={props.onAddBookmark}>
          添加书签
        </Button>
        <ScrollArea className="h-[min(48vh,22rem)]">
          <h3 className="text-muted-foreground px-1 pt-2 text-xs">书签</h3>
          {props.bookmarks.map((item) => (
            <div key={item.id} className="flex items-center gap-1">
              <button
                type="button"
                className="hover:bg-muted min-w-0 flex-1 truncate rounded-md px-2 py-1.5 text-left text-sm"
                onClick={() => props.onGo(item.locator)}
              >
                {item.title || item.locator}
              </button>
              <Button
                type="button"
                size="xs"
                variant="ghost"
                onClick={() => props.onDeleteBookmark(item.id)}
              >
                删除
              </Button>
            </div>
          ))}
          <h3 className="text-muted-foreground px-1 pt-3 text-xs">书摘</h3>
          {props.excerpts.map((item) => (
            <button
              key={item.id}
              type="button"
              className="hover:bg-muted block w-full truncate rounded-md px-2 py-1.5 text-left text-sm"
              onClick={() => props.onGo(item.locator)}
            >
              {item.quote}
            </button>
          ))}
        </ScrollArea>
      </TabsContent>
      {!props.mobile ? (
        <TabsContent value="style" className="grid gap-4 px-4 py-2">
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
        </TabsContent>
      ) : null}
    </Tabs>
  )
}

export function ReaderSidebar(props: Props) {
  const body = (
    <SidebarBody
      mobile={props.mobile}
      toc={props.toc}
      query={props.query}
      hits={props.hits}
      bookmarks={props.bookmarks}
      excerpts={props.excerpts}
      settings={props.settings}
      onPatch={props.onPatch}
      onQuery={props.onQuery}
      onSearch={props.onSearch}
      onGo={props.onGo}
      onAddBookmark={props.onAddBookmark}
      onDeleteBookmark={props.onDeleteBookmark}
    />
  )

  if (props.mobile) {
    return (
      <Sheet open={props.open} onOpenChange={(open) => !open && props.onClose()}>
        <SheetContent side="bottom" className="max-h-[80dvh] gap-0 pb-[max(env(safe-area-inset-bottom,0px),var(--leeef-safe-bottom,0px))]">
          <SheetHeader>
            <SheetTitle>目录与书签</SheetTitle>
          </SheetHeader>
          {body}
        </SheetContent>
      </Sheet>
    )
  }

  if (!props.open) return null
  return (
    <div className="reader-sidebar-layer">
      <button type="button" className="reader-sidebar-backdrop" aria-label="关闭侧栏" onClick={props.onClose} />
      <aside className="reader-sidebar">
        {body}
      </aside>
    </div>
  )
}
