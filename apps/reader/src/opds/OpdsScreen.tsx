import { useEffect, useState } from 'react'
import { toast } from 'sonner'
import { api, type Settings } from '../api'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'

type FeedItem = { title: string; href?: string; author?: string }

export function OpdsScreen() {
  const [settings, setSettings] = useState<Settings>({})
  const [url, setUrl] = useState('https://opds.feedbooks.net/catalog.atom')
  const [items, setItems] = useState<FeedItem[]>([])

  useEffect(() => {
    void api.getSettings().then((value) => {
      setSettings(value)
      if (value.opdsCatalogs?.[0]?.url) setUrl(value.opdsCatalogs[0].url)
    })
  }, [])

  const load = async () => {
    try {
      const xml = await (await fetch(url)).text()
      const doc = new DOMParser().parseFromString(xml, 'text/xml')
      const entries = [...doc.querySelectorAll('entry')].map((entry) => ({
        title: entry.querySelector('title')?.textContent ?? '未命名',
        author: entry.querySelector('author name')?.textContent ?? '',
        href:
          entry.querySelector('link[rel="http://opds-spec.org/acquisition"]')?.getAttribute('href') ??
          entry.querySelector('link')?.getAttribute('href') ??
          undefined,
      }))
      setItems(entries)
      await api.saveSettings({ ...settings, opdsCatalogs: [{ name: '当前目录', url }] })
    } catch (cause) {
      toast.error(String(cause))
    }
  }

  return (
    <main className="px-4 pt-4 pb-6">
      <header className="mb-4 flex items-center justify-between gap-3">
        <h1 className="font-heading text-2xl">OPDS</h1>
        <Button onClick={() => void load()}>浏览</Button>
      </header>
      <Input className="mb-4" value={url} onChange={(event) => setUrl(event.target.value)} />
      <div className="grid gap-3">
        {items.map((item) => (
          <Card key={`${item.title}-${item.href}`} size="sm">
            <CardHeader>
              <CardTitle>{item.title}</CardTitle>
            </CardHeader>
            <CardContent className="flex items-center justify-between gap-3">
              <span className="text-muted-foreground text-sm">{item.author}</span>
              {item.href ? (
                <Button size="sm" variant="outline" asChild>
                  <a href={item.href} target="_blank" rel="noreferrer">
                    打开
                  </a>
                </Button>
              ) : null}
            </CardContent>
          </Card>
        ))}
      </div>
    </main>
  )
}
