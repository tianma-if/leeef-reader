import { Bookmark, ChevronLeft, PanelLeft } from 'lucide-react'
import { Button } from '@/components/ui/button'

type Props = {
  title: string
  chapter: string
  progress: number
  visible: boolean
  bookmarked: boolean
  mobile: boolean
  onBack: () => void
  onToggleBookmark: () => void
  onOpenSidebar: () => void
  onKeepVisible: () => void
  onRequestHide: () => void
}

export function ReaderChrome({
  title,
  chapter,
  progress,
  visible,
  bookmarked,
  mobile,
  onBack,
  onToggleBookmark,
  onOpenSidebar,
  onKeepVisible,
  onRequestHide,
}: Props) {
  return (
    <>
      <p className="reader-band reader-band-top">{chapter || title}</p>
      <p className="reader-band reader-band-bottom">{(progress * 100).toFixed(1)}%</p>
      {bookmarked ? <span className="reader-ribbon" aria-hidden /> : null}

      {!mobile ? (
        <>
          <div
            className="reader-hover-strip reader-hover-strip-top"
            onMouseEnter={onKeepVisible}
          />
          <div
            className="reader-hover-strip reader-hover-strip-bottom"
            onMouseEnter={onKeepVisible}
          />
        </>
      ) : null}

      <header
        className={visible ? 'reader-header' : 'reader-header is-hidden'}
        onMouseEnter={!mobile ? onKeepVisible : undefined}
        onMouseLeave={!mobile ? onRequestHide : undefined}
      >
        <Button type="button" variant="ghost" size="sm" onClick={onBack}>
          <ChevronLeft />
          书架
        </Button>
        <strong>{title}</strong>
        <Button
          type="button"
          variant="ghost"
          size="icon-sm"
          aria-label={bookmarked ? '取消书签' : '添加书签'}
          onClick={onToggleBookmark}
        >
          <Bookmark className={bookmarked ? 'fill-current' : undefined} />
        </Button>
        {!mobile ? (
          <Button type="button" variant="ghost" size="icon-sm" aria-label="目录" onClick={onOpenSidebar}>
            <PanelLeft />
          </Button>
        ) : null}
      </header>
    </>
  )
}
