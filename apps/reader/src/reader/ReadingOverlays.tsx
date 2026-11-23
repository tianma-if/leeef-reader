import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

type Picture = { src: string; alt: string }

type Props = {
  footnote: string | null
  picture: Picture | null
  table: HTMLTableElement | null
  externalHref: string | null
  onCloseFootnote: () => void
  onClosePicture: () => void
  onCloseTable: () => void
  onCloseExternal: () => void
  onOpenExternal: () => void
}

export function ReadingOverlays({
  footnote,
  picture,
  table,
  externalHref,
  onCloseFootnote,
  onClosePicture,
  onCloseTable,
  onCloseExternal,
  onOpenExternal,
}: Props) {
  return (
    <>
      <Dialog open={footnote !== null} onOpenChange={(open) => !open && onCloseFootnote()}>
        <DialogContent className="max-h-[70vh] overflow-auto">
          <DialogHeader>
            <DialogTitle>脚注</DialogTitle>
            <DialogDescription className="text-foreground text-base leading-relaxed whitespace-pre-wrap">{footnote}</DialogDescription>
          </DialogHeader>
        </DialogContent>
      </Dialog>
      <Dialog open={picture !== null} onOpenChange={(open) => !open && onClosePicture()}>
        <DialogContent className="max-w-[min(92vw,48rem)]">
          <DialogHeader>
            <DialogTitle>插图</DialogTitle>
          </DialogHeader>
          {picture ? <img className="mx-auto max-h-[70vh] max-w-full object-contain" src={picture.src} alt={picture.alt || '插图'} /> : null}
        </DialogContent>
      </Dialog>
      <Dialog open={table !== null} onOpenChange={(open) => !open && onCloseTable()}>
        <DialogContent className="max-h-[80vh] max-w-[min(92vw,56rem)] overflow-auto">
          <DialogHeader>
            <DialogTitle>表格</DialogTitle>
          </DialogHeader>
          <div
            className="reader-table-view"
            ref={(host) => {
              if (host && table) host.replaceChildren(table)
            }}
          />
        </DialogContent>
      </Dialog>
      <Dialog open={externalHref !== null} onOpenChange={(open) => !open && onCloseExternal()}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>打开外部链接</DialogTitle>
            <DialogDescription className="break-all">{externalHref}</DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={onCloseExternal}>取消</Button>
            <Button type="button" onClick={onOpenExternal}>打开</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}
