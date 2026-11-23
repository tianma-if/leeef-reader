import { useState } from 'react'
import { Bookmark, Bot, Check, Copy, Highlighter, MessageSquarePlus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'

export type SelectionState = {
  text: string
  cfi: string
  x: number
  y: number
  bottom: number
}

const HIGHLIGHT_COLORS = [
  { id: '#c4a35a', label: '金色', bg: 'bg-[#c4a35a]' },
  { id: '#529b6f', label: '青绿', bg: 'bg-[#529b6f]' },
  { id: '#488bc2', label: '天蓝', bg: 'bg-[#488bc2]' },
  { id: '#c25272', label: '桃粉', bg: 'bg-[#c25272]' },
]

type Props = {
  selection: SelectionState
  mobile: boolean
  onCopy: () => void
  onSave: (color: string, note?: string) => Promise<void>
  onBookmark: () => void
  onAiExplain?: (text: string) => void
}

export function SelectionPopup({
  selection,
  mobile,
  onCopy,
  onSave,
  onBookmark,
  onAiExplain,
}: Props) {
  const [selectedColor, setSelectedColor] = useState(HIGHLIGHT_COLORS[0].id)
  const [showNoteInput, setShowNoteInput] = useState(false)
  const [noteText, setNoteText] = useState('')
  const [saving, setSaving] = useState(false)

  const safeX = Math.max(172, Math.min(window.innerWidth - 172, selection.x))
  const isNearTop = selection.y < 100
  const dockAtTop = showNoteInput || (selection.bottom > window.innerHeight - 96 && selection.y > 160)

  const save = async (note?: string) => {
    setSaving(true)
    try {
      await onSave(selectedColor, note?.trim() || undefined)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div
      className={['reader-selection p-1.5', mobile && 'is-mobile', dockAtTop && 'is-top'].filter(Boolean).join(' ')}
      style={mobile ? undefined : {
        left: safeX,
        top: isNearTop ? Math.max(8, Math.min(120, selection.bottom + 8)) : Math.min(selection.y - 8, window.innerHeight - 8),
        transform: isNearTop ? 'translate(-50%, 0)' : 'translate(-50%, -100%)',
      }}
      onMouseDown={(event) => {
        if ((event.target as Element).closest('button')) event.preventDefault()
      }}
    >
      <div className="flex flex-wrap items-center gap-1">
        <Button
          type="button"
          size={mobile ? 'sm' : 'xs'}
          onClick={() => void save(showNoteInput ? noteText : undefined)}
          disabled={saving}
        >
          <Highlighter className="size-3.5" />
          存书摘
        </Button>
        <Button type="button" size={mobile ? 'sm' : 'xs'} variant="ghost" onClick={onCopy} title="复制文字">
          <Copy className="size-3.5" />
          复制
        </Button>
        <Button
          type="button"
          size={mobile ? 'sm' : 'xs'}
          variant={showNoteInput ? 'secondary' : 'ghost'}
          onClick={() => setShowNoteInput((v) => !v)}
          title="写想法"
        >
          <MessageSquarePlus className="size-3.5" />
          想法
        </Button>
        <Button type="button" size={mobile ? 'sm' : 'xs'} variant="ghost" onClick={onBookmark} title="添加书签">
          <Bookmark className="size-3.5" />
          书签
        </Button>
        {onAiExplain ? (
          <Button
            type="button"
            size={mobile ? 'sm' : 'xs'}
            variant="ghost"
            onClick={() => onAiExplain(selection.text)}
            title="AI 解释"
          >
            <Bot className="size-3.5 text-primary" />
            AI 解释
          </Button>
        ) : null}
      </div>

      {/* Color picker row */}
      <div className="flex items-center justify-between border-t border-border/50 px-1 pt-1.5 mt-1">
        <span className="text-[10px] text-muted-foreground">划线颜色</span>
        <div className="flex items-center gap-1.5">
          {HIGHLIGHT_COLORS.map((item) => (
            <button
              key={item.id}
              type="button"
              className={`size-3.5 rounded-full transition-transform ${item.bg} ${
                selectedColor === item.id ? 'ring-2 ring-primary ring-offset-1 scale-110' : 'opacity-70 hover:opacity-100'
              }`}
              title={item.label}
              aria-label={item.label}
              aria-pressed={selectedColor === item.id}
              onClick={() => setSelectedColor(item.id)}
            />
          ))}
        </div>
      </div>

      {/* Note input field if opened */}
      {showNoteInput ? (
        <div className="mt-1.5 flex items-center gap-1 border-t border-border/50 pt-1.5">
          <Input
            value={noteText}
            onChange={(e) => setNoteText(e.target.value)}
            placeholder="写下你的想法…"
            className="h-7 text-xs flex-1"
            autoFocus
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.nativeEvent.isComposing && !saving) void save(noteText)
            }}
          />
          <Button size="xs" disabled={saving} onClick={() => void save(noteText)}>
            <Check className="size-3" />
            保存
          </Button>
        </div>
      ) : null}
    </div>
  )
}
