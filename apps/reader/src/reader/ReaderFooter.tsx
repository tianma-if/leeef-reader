import { ChevronLeft, ChevronRight, List, Palette, SlidersHorizontal, Type } from 'lucide-react'
import { Button } from '@/components/ui/button'
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
  onOpenTab: (tab: FooterTab) => void
  onPatch: (partial: Partial<Settings>) => void
  onGoToFraction: (value: number) => void
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
  onOpenTab,
  onPatch,
  onGoToFraction,
  onTurn,
  onKeepVisible,
  onRequestHide,
}: Props) {
  const theme = settings.theme ?? 'paper'
  const fontSize = settings.fontSize ?? 18
  const lineHeight = settings.lineHeight ?? 1.65
  const flow = settings.flow ?? 'paginated'
  const columns = settings.columns ?? 1

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
            <div className="reader-footer-panel grid gap-2">
              <p className="text-muted-foreground truncate text-sm">{chapter}</p>
              <Slider
                min={0}
                max={1000}
                value={[Math.round(progress * 1000)]}
                onValueChange={([value]) => onGoToFraction(value / 1000)}
              />
            </div>
          ) : null}
          <div className="reader-footer-bar">
            <Button type="button" variant="ghost" size="icon" aria-label="目录" onClick={() => onOpenTab('toc')}>
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
            <Button type="button" variant="ghost" size="icon-sm" aria-label="上一页" onClick={() => onTurn(false)}>
              <ChevronLeft />
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
            <Button type="button" variant="ghost" size="icon-sm" aria-label="下一页" onClick={() => onTurn(true)}>
              <ChevronRight />
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
