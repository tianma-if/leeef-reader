import { ChevronLeft, ChevronRight, ChevronsLeft, ChevronsRight, List, Palette, Redo2, SlidersHorizontal, Type, Undo2 } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Slider } from '@/components/ui/slider'
import type { Settings } from '../api'
import { THEMES, type ThemeName } from './bookStyles'
import { FontPicker } from './FontPicker'
import type { FooterTab } from './useReaderChrome'

type Props = {
  mobile: boolean
  visible: boolean
  footerTab: FooterTab
  settings: Settings
  progress: number
  chapter: string
  canGoBack: boolean
  canGoForward: boolean
  locationCurrent: number | null
  locationTotal: number | null
  onOpenTab: (tab: FooterTab) => void
  onPatch: (partial: Partial<Settings>) => void
  onGoToFraction: (value: number) => void
  onGoToLocation: (page: number) => void
  onHistory: (forward: boolean) => void
  onSection: (forward: boolean) => void
  onTurn: (forward: boolean) => void
  onKeepVisible: () => void
  onRequestHide: () => void
}

export function ReaderFooter({
  mobile,
  visible,
  footerTab,
  settings,
  progress,
  chapter,
  canGoBack,
  canGoForward,
  locationCurrent,
  locationTotal,
  onOpenTab,
  onPatch,
  onGoToFraction,
  onGoToLocation,
  onHistory,
  onSection,
  onTurn,
  onKeepVisible,
  onRequestHide,
}: Props) {
  const theme = settings.theme ?? 'paper'
  const fontSize = settings.fontSize ?? 18
  const lineHeight = settings.lineHeight ?? 1.65
  const flow = settings.flow ?? 'paginated'
  const columns = settings.columns ?? 1
  const pageTurn = settings.pageTurn ?? 'push'
  const navigation = (
    <ReadingNavigation
      canGoBack={canGoBack}
      canGoForward={canGoForward}
      locationCurrent={locationCurrent}
      locationTotal={locationTotal}
      onGoToLocation={onGoToLocation}
      onHistory={onHistory}
      onSection={onSection}
      onTurn={onTurn}
    />
  )

  return (
    <footer
      className={visible ? 'reader-footer' : 'reader-footer is-hidden'}
      onMouseEnter={!mobile ? onKeepVisible : undefined}
      onMouseLeave={!mobile ? onRequestHide : undefined}
    >
      {mobile ? (
        <>
          {footerTab === 'theme' ? (
            <div className="reader-footer-panel">
              <div className="flex flex-wrap gap-2">
                {(Object.keys(THEMES) as ThemeName[]).map((name) => (
                  <Button
                    key={name}
                    type="button"
                    size="sm"
                    variant={theme === name ? 'default' : 'outline'}
                    onClick={() => onPatch({ theme: name })}
                  >
                    {THEMES[name].name}
                  </Button>
                ))}
              </div>
            </div>
          ) : null}
          {footerTab === 'font' ? (
            <div className="reader-footer-panel grid gap-3">
              <FontPicker
                value={settings.fontFamily}
                onChange={(fontFamily) => onPatch({ fontFamily })}
              />
              <label className="grid gap-2 text-sm">
                字号 {fontSize}
                <Slider
                  min={14}
                  max={28}
                  value={[fontSize]}
                  onValueChange={([value]) => onPatch({ fontSize: value })}
                />
              </label>
              <label className="grid gap-2 text-sm">
                行距 {lineHeight.toFixed(2)}
                <Slider
                  min={1.3}
                  max={2.2}
                  step={0.05}
                  value={[lineHeight]}
                  onValueChange={([value]) => onPatch({ lineHeight: value })}
                />
              </label>
              {flow === 'paginated' ? (
                <div className="flex flex-wrap gap-2">
                  <Button
                    type="button"
                    size="sm"
                    variant={pageTurn === 'push' ? 'default' : 'outline'}
                    onClick={() => onPatch({ pageTurn: 'push' })}
                  >
                    推移
                  </Button>
                  <Button
                    type="button"
                    size="sm"
                    variant={pageTurn === 'slide' ? 'default' : 'outline'}
                    onClick={() => onPatch({ pageTurn: 'slide' })}
                  >
                    滑动
                  </Button>
                </div>
              ) : null}
              <div className="flex flex-wrap gap-2">
                <Button
                  type="button"
                  size="sm"
                  variant={flow === 'paginated' ? 'default' : 'outline'}
                  onClick={() => onPatch({ flow: 'paginated' })}
                >
                  分页
                </Button>
                <Button
                  type="button"
                  size="sm"
                  variant={flow === 'scrolled' ? 'default' : 'outline'}
                  onClick={() => onPatch({ flow: 'scrolled' })}
                >
                  滚动
                </Button>
                <Button
                  type="button"
                  size="sm"
                  variant={columns === 1 ? 'default' : 'outline'}
                  onClick={() => onPatch({ columns: 1 })}
                >
                  单栏
                </Button>
                <Button
                  type="button"
                  size="sm"
                  variant={columns === 2 ? 'default' : 'outline'}
                  onClick={() => onPatch({ columns: 2 })}
                >
                  双栏
                </Button>
              </div>
            </div>
          ) : null}
          {footerTab === 'progress' ? (
            <div className="reader-footer-panel grid gap-3">
              <p className="text-muted-foreground truncate text-sm">{chapter}</p>
              <Slider
                min={0}
                max={1000}
                value={[Math.round(progress * 1000)]}
                onValueChange={([value]) => onGoToFraction(value / 1000)}
              />
              {navigation}
            </div>
          ) : null}
          <div className="reader-footer-bar">
            <Button type="button" variant="ghost" aria-label="目录" aria-haspopup="dialog" className="size-11" onClick={() => onOpenTab('toc')}>
              <List />
            </Button>
            <Button type="button" variant="ghost" size="icon" aria-label="主题" onClick={() => onOpenTab('theme')}>
              <Palette />
            </Button>
            <Button type="button" variant="ghost" size="icon" aria-label="进度" onClick={() => onOpenTab('progress')}>
              <SlidersHorizontal />
            </Button>
            <Button type="button" variant="ghost" size="icon" aria-label="字体排版" onClick={() => onOpenTab('font')}>
              <Type />
            </Button>
          </div>
        </>
      ) : (
        <>
          {footerTab === 'font' ? (
            <div className="reader-footer-panel grid gap-3">
              <FontPicker
                value={settings.fontFamily}
                onChange={(fontFamily) => onPatch({ fontFamily })}
              />
              <label className="grid gap-2 text-sm">
                字号 {fontSize}
                <Slider
                  min={14}
                  max={28}
                  value={[fontSize]}
                  onValueChange={([value]) => onPatch({ fontSize: value })}
                />
              </label>
              <label className="grid gap-2 text-sm">
                行距 {lineHeight.toFixed(2)}
                <Slider
                  min={1.3}
                  max={2.2}
                  step={0.05}
                  value={[lineHeight]}
                  onValueChange={([value]) => onPatch({ lineHeight: value })}
                />
              </label>
            </div>
          ) : null}
          <div className="reader-footer-desktop">
            <Button type="button" variant="ghost" size="icon-sm" aria-label="上一章" onClick={() => onSection(false)}>
              <ChevronsLeft />
            </Button>
            <Button type="button" variant="ghost" size="icon-sm" aria-label="上一页" onClick={() => onTurn(false)}>
              <ChevronLeft />
            </Button>
            <Button type="button" variant="ghost" size="icon-sm" aria-label="返回上一位置" disabled={!canGoBack} onClick={() => onHistory(false)}>
              <Undo2 />
            </Button>
            <Slider
              className="flex-1"
              min={0}
              max={1000}
              value={[Math.round(progress * 1000)]}
              onValueChange={([value]) => onGoToFraction(value / 1000)}
            />
            <span className="text-muted-foreground w-14 text-right text-xs">
              {(progress * 100).toFixed(1)}%
            </span>
            <Button type="button" variant="ghost" size="icon-sm" aria-label="前进到下一位置" disabled={!canGoForward} onClick={() => onHistory(true)}>
              <Redo2 />
            </Button>
            <Button type="button" variant="ghost" size="icon-sm" aria-label="下一页" onClick={() => onTurn(true)}>
              <ChevronRight />
            </Button>
            <Button type="button" variant="ghost" size="icon-sm" aria-label="下一章" onClick={() => onSection(true)}>
              <ChevronsRight />
            </Button>
            <Button
              type="button"
              variant={footerTab === 'font' ? 'secondary' : 'ghost'}
              size="icon-sm"
              aria-label="字体"
              onClick={() => onOpenTab('font')}
            >
              <Type />
            </Button>
          </div>
        </>
      )}
    </footer>
  )
}

function ReadingNavigation({
  canGoBack,
  canGoForward,
  locationCurrent,
  locationTotal,
  onGoToLocation,
  onHistory,
  onSection,
  onTurn,
}: {
  canGoBack: boolean
  canGoForward: boolean
  locationCurrent: number | null
  locationTotal: number | null
  onGoToLocation: (page: number) => void
  onHistory: (forward: boolean) => void
  onSection: (forward: boolean) => void
  onTurn: (forward: boolean) => void
}) {
  const [draft, setDraft] = useState(locationCurrent ? String(locationCurrent) : '')
  const [editing, setEditing] = useState(false)
  useEffect(() => {
    if (!editing) setDraft(locationCurrent ? String(locationCurrent) : '')
  }, [editing, locationCurrent])

  return (
    <div className="grid gap-3">
      {locationTotal ? (
        <form
          className="flex items-center justify-center gap-2 text-sm"
          onSubmit={(event) => {
            event.preventDefault()
            const page = Number(draft)
            if (Number.isInteger(page)) onGoToLocation(page)
          }}
        >
          <Input
            className="h-8 w-20 text-center"
            inputMode="numeric"
            aria-label="跳转到位置"
            value={draft}
            onFocus={() => setEditing(true)}
            onBlur={() => setEditing(false)}
            onChange={(event) => setDraft(event.target.value)}
          />
          <span className="text-muted-foreground">/ {locationTotal}</span>
        </form>
      ) : null}
      <div className="flex items-center justify-between gap-1">
        <Button type="button" variant="ghost" size="icon" aria-label="上一章" onClick={() => onSection(false)}>
          <ChevronsLeft />
        </Button>
        <Button type="button" variant="ghost" size="icon" aria-label="上一页" onClick={() => onTurn(false)}>
          <ChevronLeft />
        </Button>
        <Button type="button" variant="ghost" size="icon" aria-label="返回上一位置" disabled={!canGoBack} onClick={() => onHistory(false)}>
          <Undo2 />
        </Button>
        <Button type="button" variant="ghost" size="icon" aria-label="前进到下一位置" disabled={!canGoForward} onClick={() => onHistory(true)}>
          <Redo2 />
        </Button>
        <Button type="button" variant="ghost" size="icon" aria-label="下一页" onClick={() => onTurn(true)}>
          <ChevronRight />
        </Button>
        <Button type="button" variant="ghost" size="icon" aria-label="下一章" onClick={() => onSection(true)}>
          <ChevronsRight />
        </Button>
      </div>
    </div>
  )
}
