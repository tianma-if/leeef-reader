import { useEffect, useState } from 'react'
import { Download } from 'lucide-react'
import { toast } from 'sonner'
import { api, type Book, type Excerpt } from '../api'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
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
  const [exporting, setExporting] = useState(false)
  const [editing, setEditing] = useState<{ id: string; quote: string; note: string } | null>(null)

  useEffect(() => {
    void Promise.all([api.listExcerpts(), api.listBooks()])
      .then(([nextItems, nextBooks]) => {
        setItems(nextItems)
        setBooks(nextBooks)
      })
      .catch((cause) => toast.error(String(cause)))
  }, [])

  const visible = items.filter((item) =>
    `${item.quote} ${item.note ?? ''} ${item.bookTitle ?? ''}`
      .toLowerCase()
      .includes(query.toLowerCase()),
  )
  const allDocuments = groupExcerptsByBook(items, books)
  const documents = groupExcerptsByBook(visible, books)

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

  return (
    <main className="px-4 pt-4 pb-6">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
        <h1 className="font-heading text-2xl">笔记</h1>
        {allDocuments.length > 0 ? (
          <div className="flex gap-2">
            <Button
              size="sm"
              variant="outline"
              disabled={exporting}
              onClick={() => void exportDocuments(allDocuments, 'markdown')}
            >
              <Download /> 全部 Markdown
            </Button>
            <Button
              size="sm"
              variant="outline"
              disabled={exporting}
              onClick={() => void exportDocuments(allDocuments, 'txt')}
            >
              <Download /> 全部 TXT
            </Button>
          </div>
        ) : null}
      </div>
      <Input
        className="mb-4"
        value={query}
        onChange={(event) => setQuery(event.target.value)}
        placeholder="搜索书摘和笔记"
      />
      {visible.length === 0 ? (
        <p className="text-muted-foreground">还没有书摘。阅读时选中文字即可添加。</p>
      ) : (
        <div className="grid gap-6">
          {documents.map((document) => (
            <section key={document.bookId} className="grid gap-3">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div>
                  <h2 className="font-heading text-lg">{document.title}</h2>
                  <p className="text-muted-foreground text-xs">
                    {document.author ? `${document.author} · ` : ''}
                    {document.excerpts.length} 条书摘
                  </p>
                </div>
                <div className="flex gap-2">
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
                <Card key={item.id} size="sm">
                  <CardContent className="space-y-2">
                    {editing?.id === item.id ? (
                      <>
                        <Textarea
                          value={editing.quote}
                          onChange={(event) => setEditing({ ...editing, quote: event.target.value })}
                          aria-label="书摘原文"
                        />
                        <Textarea
                          value={editing.note}
                          onChange={(event) => setEditing({ ...editing, note: event.target.value })}
                          placeholder="笔记（可选）"
                          aria-label="书摘笔记"
                        />
                      </>
                    ) : (
                      <>
                        <p className="whitespace-pre-wrap">{item.quote}</p>
                        {item.note ? (
                          <p className="text-muted-foreground whitespace-pre-wrap">{item.note}</p>
                        ) : null}
                      </>
                    )}
                    <p className="text-muted-foreground text-xs">
                      摘录于 {excerptDate(item.createdAt)}
                    </p>
                    <div className="flex gap-2">
                      {editing?.id === item.id ? (
                        <>
                          <Button
                            size="sm"
                            onClick={() => {
                              const draft = editing
                              if (!draft.quote.trim()) {
                                toast.error('书摘原文不能为空')
                                return
                              }
                              void api.updateExcerpt({
                                id: item.id,
                                quote: draft.quote,
                                note: draft.note || undefined,
                                color: item.color,
                              }).then(() => api.listExcerpts()).then((next) => {
                                setItems(next)
                                setEditing(null)
                                toast.success('已更新，并已加入 EdgeEver 同步队列')
                              }).catch((cause) => toast.error(String(cause)))
                            }}
                          >
                            保存
                          </Button>
                          <Button size="sm" variant="ghost" onClick={() => setEditing(null)}>
                            取消
                          </Button>
                        </>
                      ) : (
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => setEditing({
                            id: item.id,
                            quote: item.quote,
                            note: item.note ?? '',
                          })}
                        >
                          编辑
                        </Button>
                      )}
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => onOpenBook(item.bookId, item.locator)}
                      >
                        打开
                      </Button>
                      <Button
                        size="sm"
                        variant="destructive"
                        onClick={() =>
                          void api.deleteExcerpt(item.id).then(() => {
                            void api.listExcerpts().then(setItems)
                            toast.success('已删除')
                          })
                        }
                      >
                        删除
                      </Button>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </section>
          ))}
        </div>
      )}
    </main>
  )
}
