import { Bookmark, Copy, Highlighter } from 'lucide-react'
import { Button } from '@/components/ui/button'

export type SelectionState = {
  text: string
  cfi: string
  x: number
  y: number
}

type Props = {
  selection: SelectionState
  onCopy: () => void
  onHighlight: () => void
  onBookmark: () => void
}

export function SelectionPopup({ selection, onCopy, onHighlight, onBookmark }: Props) {
  return (
    <div
      className="reader-selection"
      style={{ left: selection.x, top: selection.y }}
    >
      <Button type="button" size="sm" variant="ghost" onClick={onCopy}>
        <Copy />
        复制
      </Button>
      <Button type="button" size="sm" variant="ghost" onClick={onHighlight}>
        <Highlighter />
        划线
      </Button>
      <Button type="button" size="sm" variant="ghost" onClick={onBookmark}>
        <Bookmark />
        书签
      </Button>
    </div>
  )
}
