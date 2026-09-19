import { useEffect, useState } from 'react'
import { toast } from 'sonner'
import { api, type Excerpt } from '../api'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'

type Props = { onOpenBook: (bookId: string, locator?: string) => void }

export function NotesScreen({ onOpenBook }: Props) {
  const [items, setItems] = useState<Excerpt[]>([])
  const [query, setQuery] = useState('')

  useEffect(() => {
    void api.listExcerpts().then(setItems)
  }, [])

  const visible = items.filter((item) =>
    `${item.quote} ${item.note ?? ''} ${item.bookTitle ?? ''}`
      .toLowerCase()
      .includes(query.toLowerCase()),
  )

  return (
    <main className="px-4 pt-4 pb-6">
      <h1 className="font-heading mb-4 text-2xl">笔记</h1>
      <Input
        className="mb-4"
        value={query}
        onChange={(event) => setQuery(event.target.value)}
        placeholder="搜索书摘和笔记"
      />
      {visible.length === 0 ? (
        <p className="text-muted-foreground">还没有书摘。阅读时选中文字即可添加。</p>
      ) : (
        <div className="grid gap-3">
          {visible.map((item) => (
            <Card key={item.id} size="sm">
              <CardHeader>
                <CardTitle>{item.bookTitle}</CardTitle>
              </CardHeader>
              <CardContent className="space-y-2">
                <p>{item.quote}</p>
                {item.note ? <p className="text-muted-foreground">{item.note}</p> : null}
                <div className="flex gap-2">
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
        </div>
      )}
    </main>
  )
}
