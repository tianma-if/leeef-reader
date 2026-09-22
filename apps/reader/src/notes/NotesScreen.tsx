import { useEffect, useMemo, useState } from 'react'
import { BookOpen, Download, Search, StickyNote, Trash2 } from 'lucide-react'
import { toast } from 'sonner'
import { api, type Book, type Excerpt } from '../api'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  excerptExportContent,
  excerptDate,
  groupExcerptsByBook,
  safeExportFilename,
  type BookExcerptDocument,
  type ExcerptExportFormat,
} from './exportExcerpts'
import { saveTextExport } from './saveExport'
import { Textarea } from '@/components/ui/textarea'

type Props = { onOpenBook: (bookId: string, locator?: string) => void }

export function NotesScreen({ onOpenBook }: Props) {
  const [items, setItems] = useState<Excerpt[]>([])
  const [books, setBooks] = useState<Book[]>([])
  const [query, setQuery] = useState('')
  const [selectedBookId, setSelectedBookId] = useState<string>('all')
  const [exporting, setExporting] = useState(false)
  const [editing, setEditing] = useState<{ id: string; quote: string; note: string } | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<Excerpt | null>(null)

  useEffect(() => {
    void Promise.all([api.listExcerpts(), api.listBooks()])
      .then(([nextItems, nextBooks]) => {
        setItems(nextItems)
        setBooks(nextBooks)
      })
      .catch((cause) => toast.error(String(cause)))
  }, [])

  const visible = useMemo(() => {
    return items.filter((item) => {
      if (selectedBookId !== 'all' && item.bookId !== selectedBookId) return false
      const hay = `${item.quote} ${item.note ?? ''} ${item.bookTitle ?? ''}`.toLowerCase()
      return !query || hay.includes(query.toLowerCase())
    })
  }, [items, selectedBookId, query])

  const allDocuments = useMemo(() => groupExcerptsByBook(items, books), [items, books])
  const documents = useMemo(() => groupExcerptsByBook(visible, books), [visible, books])

  const exportDocuments = async (
    selected: BookExcerptDocument[],
    format: ExcerptExportFormat,
  ) => {
    if (!selected.length) return
    setExporting(true)
    try {
      const title = selected.length === 1 ? selected[0].title : 'Leeef Reader'
      const saved = await saveTextExport(
        safeExportFilename(title, format),
        excerptExportContent(selected, format),
      )
      if (saved) toast.success('书摘已导出')
    } catch (cause) {
      toast.error(`导出失败：${String(cause)}`)
    } finally {
      setExporting(false)
    }
  }

  const handleDeleteConfirmed = async () => {
    if (!deleteTarget) return
    try {
      await api.deleteExcerpt(deleteTarget.id)
      const next = await api.listExcerpts()
      setItems(next)
      setDeleteTarget(null)
      toast.success('书摘已删除')
    } catch (e) {
      toast.error(String(e))
    }
  }

  return (
    <main className="px-4 pt-4 pb-8 max-w-4xl mx-auto">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="font-heading text-2xl">笔记与书摘</h1>
          <p className="text-xs text-muted-foreground mt-0.5">
            共 {items.length} 条记录，支持双向同步与导出
          </p>
        </div>
        {allDocuments.length > 0 ? (
          <div className="flex gap-2">
            <Button
              size="sm"
              variant="outline"
              disabled={exporting}
              onClick={() => void exportDocuments(allDocuments, 'markdown')}
            >
              <Download className="size-3.5 mr-1" />
              导出 Markdown
            </Button>
            <Button
              size="sm"
              variant="outline"
              disabled={exporting}
              onClick={() => void exportDocuments(allDocuments, 'txt')}
            >
              <Download className="size-3.5 mr-1" />
              导出 TXT
            </Button>
          </div>
        ) : null}
      </div>

      {/* Filter and search bar */}
      <div className="mb-6 flex flex-wrap gap-2">
        <div className="relative min-w-48 flex-1">
          <Search className="absolute left-2.5 top-2.5 size-4 text-muted-foreground" />
          <Input
            className="pl-8"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="搜索书摘和笔记内容…"
          />
        </div>
        <Select value={selectedBookId} onValueChange={setSelectedBookId}>
          <SelectTrigger className="w-44">
            <SelectValue placeholder="筛选书籍" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">全部书籍 ({allDocuments.length})</SelectItem>
            {allDocuments.map((doc) => (
              <SelectItem key={doc.bookId} value={doc.bookId}>
                {doc.title} ({doc.excerpts.length})
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      {visible.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 px-4 text-center">
          <div className="size-16 rounded-2xl bg-muted/60 flex items-center justify-center text-muted-foreground mb-4 shadow-inner">
            <StickyNote className="size-8 stroke-[1.5]" />
          </div>
          <h3 className="text-base font-semibold mb-1">
            {query || selectedBookId !== 'all' ? '未找到匹配的书摘' : '还没有书摘与笔记'}
          </h3>
          <p className="text-muted-foreground text-xs max-w-sm mb-4 leading-relaxed">
            {query || selectedBookId !== 'all'
              ? '请尝试更换搜索关键字或清除书籍筛选。'
              : '在阅读书籍时选中文字，点击「划线」或「想法」即可快速添加。'}
          </p>
        </div>
      ) : (
        <div className="grid gap-8">
          {documents.map((document) => (
            <section key={document.bookId} className="grid gap-3">
              <div className="flex flex-wrap items-center justify-between gap-2 border-b pb-2">
                <div className="flex items-center gap-2">
                  <BookOpen className="size-4 text-primary" />
                  <h2 className="font-heading text-base font-semibold">{document.title}</h2>
                  <span className="text-muted-foreground text-xs">
                    {document.author ? `· ${document.author}` : ''} ({document.excerpts.length}条)
                  </span>
                </div>
                <div className="flex gap-1.5">
                  <Button
                    size="xs"
                    variant="ghost"
                    disabled={exporting}
                    onClick={() => void exportDocuments([document], 'markdown')}
                  >
                    导出 MD
                  </Button>
                  <Button
                    size="xs"
                    variant="ghost"
                    disabled={exporting}
                    onClick={() => void exportDocuments([document], 'txt')}
                  >
                    导出 TXT
                  </Button>
                </div>
              </div>

              {document.excerpts.map((item) => (
                <Card
                  key={item.id}
                  size="sm"
                  className="relative overflow-hidden transition-shadow hover:shadow-xs"
                  style={{
                    borderLeftWidth: '4px',
                    borderLeftColor: item.color || '#c4a35a',
                  }}
                >
                  <CardContent className="space-y-3 pt-3">
                    {editing?.id === item.id ? (
                      <div className="space-y-2">
                        <label className="text-xs text-muted-foreground">书摘原文</label>
                        <Textarea
                          value={editing.quote}
                          onChange={(event) =>
                            setEditing({ ...editing, quote: event.target.value })
                          }
                          aria-label="书摘原文"
                          className="text-sm font-serif"
                        />
                        <label className="text-xs text-muted-foreground">我的想法与笔记</label>
                        <Textarea
                          value={editing.note}
                          onChange={(event) =>
                            setEditing({ ...editing, note: event.target.value })
                          }
                          placeholder="写下你的感悟…"
                          aria-label="书摘笔记"
                          className="text-sm"
                        />
                      </div>
                    ) : (
                      <>
                        <blockquote className="font-serif text-sm leading-relaxed border-l-2 border-muted-foreground/30 pl-3 my-1">
                          {item.quote}
                        </blockquote>
                        {item.note ? (
                          <div className="bg-muted/40 rounded-lg p-2.5 text-sm text-foreground/90 leading-normal">
                            <span className="text-[10px] uppercase font-bold text-muted-foreground tracking-wider block mb-1">
                              笔记想法
                            </span>
                            <p className="whitespace-pre-wrap">{item.note}</p>
                          </div>
                        ) : null}
                      </>
                    )}

                    <div className="flex flex-wrap items-center justify-between gap-2 pt-1 border-t border-border/40 text-xs">
                      <span className="text-muted-foreground text-[11px]">
                        摘录于 {excerptDate(item.createdAt)}
                      </span>
                      <div className="flex items-center gap-1.5">
                        {editing?.id === item.id ? (
                          <>
                            <Button
                              size="xs"
                              onClick={() => {
                                const draft = editing
                                if (!draft.quote.trim()) {
                                  toast.error('书摘原文不能为空')
                                  return
                                }
                                void api
                                  .updateExcerpt({
                                    id: item.id,
                                    quote: draft.quote,
                                    note: draft.note || undefined,
                                    color: item.color,
                                  })
                                  .then(() => api.listExcerpts())
                                  .then((next) => {
                                    setItems(next)
                                    setEditing(null)
                                    toast.success('已更新')
                                  })
                                  .catch((cause) => toast.error(String(cause)))
                              }}
                            >
                              保存
                            </Button>
                            <Button size="xs" variant="ghost" onClick={() => setEditing(null)}>
                              取消
                            </Button>
                          </>
                        ) : (
                          <Button
                            size="xs"
                            variant="ghost"
                            onClick={() =>
                              setEditing({
                                id: item.id,
                                quote: item.quote,
                                note: item.note ?? '',
                              })
                            }
                          >
                            编辑
                          </Button>
                        )}
                        <Button
                          size="xs"
                          variant="ghost"
                          onClick={() => onOpenBook(item.bookId, item.locator)}
                        >
                          定位阅读
                        </Button>
                        <Button
                          size="xs"
                          variant="ghost"
                          className="text-destructive hover:text-destructive hover:bg-destructive/10"
                          onClick={() => setDeleteTarget(item)}
                        >
                          <Trash2 className="size-3" />
                        </Button>
                      </div>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </section>
          ))}
        </div>
      )}

      {/* Delete Excerpt Confirmation Dialog */}
      <Dialog open={Boolean(deleteTarget)} onOpenChange={(open) => !open && setDeleteTarget(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>删除书摘笔记？</DialogTitle>
            <DialogDescription>
              确定要删除这条摘录吗？如果配置了云端同步，删除记录也会同步至其它设备。
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDeleteTarget(null)}>
              取消
            </Button>
            <Button variant="destructive" onClick={() => void handleDeleteConfirmed()}>
              确认删除
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </main>
  )
}
