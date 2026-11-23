import { useLayoutEffect, useRef, useState } from 'react'
import { Bookmark, Bot, Copy, Highlighter, MessageSquarePlus, Search, Trash2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Sheet, SheetContent, SheetTitle } from '@/components/ui/sheet'
import { Textarea } from '@/components/ui/textarea'
import type { Excerpt } from '../api'

export type SelectionState = {
  text: string
  cfi: string
  x: number
  y: number
  bottom: number
}

const HIGHLIGHT_COLORS = [
  { id: '#c4a35a', label: '金色' },
  { id: '#529b6f', label: '青绿' },
  { id: '#488bc2', label: '天蓝' },
  { id: '#c25272', label: '桃粉' },
]

export const DEFAULT_HIGHLIGHT_COLOR = HIGHLIGHT_COLORS[0].id

type Props = {
  selection: SelectionState
  excerpt?: Excerpt
  defaultColor: string
  mobile: boolean
  onCopy: () => void
  onColor: (color: string) => Promise<boolean>
  onOpenNote: () => void
  onSaveNote: (note: string) => Promise<boolean>
  onRemove: () => Promise<void>
  onDismiss: () => void
  onBookmark: () => void
  onSearch: () => void
  onAiExplain: () => void
}

export function SelectionPopup({
  selection,
  excerpt,
  defaultColor,
  mobile,
  onCopy,
  onColor,
  onOpenNote,
  onSaveNote,
  onRemove,
  onDismiss,
  onBookmark,
  onSearch,
  onAiExplain,
}: Props) {
  const popupRef = useRef<HTMLDivElement>(null)
  const [sheet, setSheet] = useState<HTMLDivElement | null>(null)
  const [draft, setDraft] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const editing = draft !== null
  const inSheet = mobile && editing
  const { x, y, bottom } = selection

  useLayoutEffect(() => {
    const popup = popupRef.current
    if (!popup) return
    const place = () => {
      const margin = 8
      const gap = 18
      const { width, height } = popup.getBoundingClientRect()
      const above = y - gap - height
      const below = bottom + gap
      const roomBelow = window.innerHeight - below - margin
      const top = above >= margin || roomBelow < y - gap - margin ? above : below
      popup.style.left = `${Math.max(margin, Math.min(window.innerWidth - width - margin, x - width / 2))}px`
      popup.style.top = `${Math.max(margin, Math.min(window.innerHeight - height - margin, top))}px`
    }
    place()
    const observer = new ResizeObserver(place)
    observer.observe(popup)
    window.addEventListener('resize', place)
    return () => {
      observer.disconnect()
      window.removeEventListener('resize', place)
    }
  }, [bottom, inSheet, x, y])

  useLayoutEffect(() => {
    const viewport = window.visualViewport
    if (!sheet || !viewport) return
    const update = () => {
      const bottom = Math.max(0, window.innerHeight - viewport.height - viewport.offsetTop)
      sheet.style.setProperty('--reader-viewport-bottom', `${bottom}px`)
    }
    update()
    viewport.addEventListener('resize', update)
    viewport.addEventListener('scroll', update)
    return () => {
      viewport.removeEventListener('resize', update)
      viewport.removeEventListener('scroll', update)
    }
  }, [sheet])

  const run = async (operation: () => Promise<unknown>) => {
    setSaving(true)
    try {
      await operation()
    } finally {
      setSaving(false)
    }
  }

  const saveAndDismiss = (save: () => Promise<boolean>) => run(async () => {
    if (await save()) onDismiss()
  })

  const editNote = () => {
    setDraft(excerpt?.note ?? '')
    onOpenNote()
  }

  const editor = editing ? (
    <form className="flex min-h-0 flex-col gap-3" onSubmit={(event) => {
      event.preventDefault()
      if (!saving) void saveAndDismiss(() => onSaveNote(draft.trim()))
    }}>
      <blockquote className="reader-excerpt-quote line-clamp-2 text-sm text-muted-foreground">{selection.text}</blockquote>
      <Textarea
        value={draft}
        onChange={(event) => setDraft(event.target.value)}
        className="reader-note-input"
        aria-label="批注内容"
        placeholder="写下你的想法…"
        autoFocus
        onKeyDown={(event) => {
          if (event.key === 'Escape' && !mobile && !event.nativeEvent.isComposing) {
            event.stopPropagation()
            if (!saving) onDismiss()
          }
        }}
      />
      <div className="flex shrink-0 justify-end gap-2">
        <Button type="button" variant="ghost" onClick={onDismiss} disabled={saving}>取消</Button>
        <Button type="submit" disabled={saving}>
          {draft.trim() ? '保存批注' : '仅存书摘'}
        </Button>
      </div>
    </form>
  ) : null

  if (inSheet) {
    return (
      <Sheet open onOpenChange={(open) => { if (!open && !saving) onDismiss() }}>
        <SheetContent ref={setSheet} side="bottom" showCloseButton={false} className="reader-note-sheet gap-3 rounded-t-2xl p-4" aria-describedby={undefined}>
          <SheetTitle>{excerpt?.note ? '编辑批注' : '写批注'}</SheetTitle>
          {editor}
        </SheetContent>
      </Sheet>
    )
  }

  return (
    <div
      ref={popupRef}
      className="reader-selection"
      aria-label={editor ? '书摘批注' : '选中文字操作'}
      onMouseDown={(event) => {
        if ((event.target as Element).closest('button')) event.preventDefault()
      }}
    >
      {editor ?? (
        <>
          <div className="reader-selection-colors" role="group" aria-label={excerpt ? '修改书摘颜色' : '选择颜色并保存书摘'}>
            {HIGHLIGHT_COLORS.map(({ id, label }) => (
              <button
                key={id}
                type="button"
                aria-label={excerpt ? `改成${label}高亮` : `存为${label}书摘`}
                aria-pressed={excerpt?.color === id}
                title={excerpt ? `改成${label}高亮` : `存为${label}书摘`}
                className="reader-selection-swatch"
                disabled={saving}
                onClick={() => void run(() => onColor(id))}
              >
                <span style={{ backgroundColor: id }} />
              </button>
            ))}
          </div>
          {excerpt?.note ? <p className="mx-2 line-clamp-2 text-sm text-muted-foreground">{excerpt.note}</p> : null}
          <div className="reader-selection-actions">
            {excerpt ? (
              <Button type="button" size="icon" variant="ghost" disabled={saving} onClick={() => void run(onRemove)} aria-label="移除书摘" title="移除书摘">
                <Trash2 />
              </Button>
            ) : (
              <Button type="button" disabled={saving} onClick={() => void saveAndDismiss(() => onColor(defaultColor))}>
                <Highlighter />
                存书摘
              </Button>
            )}
            <Button type="button" variant="ghost" onClick={editNote} disabled={saving}>
              <MessageSquarePlus />
              {excerpt?.note ? '编辑批注' : '批注'}
            </Button>
            <Button type="button" size="icon" variant="ghost" onClick={onCopy} disabled={saving} aria-label="复制文字" title="复制文字">
              <Copy />
            </Button>
            <Button type="button" size="icon" variant="ghost" onClick={onBookmark} disabled={saving} aria-label="添加书签" title="添加书签">
              <Bookmark />
            </Button>
            <Button type="button" size="icon" variant="ghost" onClick={onSearch} disabled={saving} aria-label="在书中搜索" title="在书中搜索">
              <Search />
            </Button>
            <Button type="button" size="icon" variant="ghost" onClick={onAiExplain} disabled={saving} aria-label="AI 解释" title="AI 解释">
              <Bot />
            </Button>
          </div>
        </>
      )}
    </div>
  )
}
