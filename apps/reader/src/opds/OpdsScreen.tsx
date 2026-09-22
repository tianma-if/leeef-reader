import { useEffect, useState } from 'react'
import { listen } from '@tauri-apps/api/event'
import { BookDown, ExternalLink, Globe, Loader2, Rss } from 'lucide-react'
import { toast } from 'sonner'
import { api, type Settings } from '../api'
import { prepareBookFile } from '../lib/bookFile'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'

type FeedItem = {
  title: string
  href?: string
  author?: string
  summary?: string
  acquisitionHref?: string
}

const PRESET_CATALOGS = [
  { name: 'Standard Ebooks', url: 'https://standardebooks.org/opds/all' },
  { name: 'Feedbooks', url: 'https://opds.feedbooks.net/catalog.atom' },
  { name: 'Project Gutenberg', url: 'https://m.gutenberg.org/ebooks.opds/' },
]

export function OpdsScreen() {
  const [settings, setSettings] = useState<Settings>({})
  const [url, setUrl] = useState('https://standardebooks.org/opds/all')
  const [items, setItems] = useState<FeedItem[]>([])
  const [loading, setLoading] = useState(false)
  const [importingHref, setImportingHref] = useState<string | null>(null)

  useEffect(() => {
    const applySettings = (value: Settings) => {
      setSettings(value)
      if (value.opdsCatalogs?.[0]?.url) setUrl(value.opdsCatalogs[0].url)
    }
    void api.getSettings().then(applySettings)
    let stop: (() => void) | undefined
    void listen('settings-synced', () => {
      void api.getSettings().then(applySettings)
    }).then((unlisten) => {
      stop = unlisten
    })
    return () => stop?.()
  }, [])

  const load = async (targetUrl?: string) => {
    const fetchUrl = targetUrl || url
    if (!fetchUrl.trim()) return
    setLoading(true)
    try {
      const response = await fetch(fetchUrl)
      if (!response.ok) throw new Error(`网络响应错误: ${response.status}`)
      const xml = await response.text()
      const doc = new DOMParser().parseFromString(xml, 'text/xml')
      const entries = [...doc.querySelectorAll('entry')].map((entry) => {
        const acqLink = entry.querySelector('link[rel*="acquisition"]')
        const genericLink = entry.querySelector('link[type*="epub"]') || entry.querySelector('link')
        return {
          title: entry.querySelector('title')?.textContent ?? '未命名',
          author: entry.querySelector('author name')?.textContent ?? '',
          summary: entry.querySelector('summary')?.textContent ?? '',
          acquisitionHref: acqLink?.getAttribute('href') ?? undefined,
          href: acqLink?.getAttribute('href') ?? genericLink?.getAttribute('href') ?? undefined,
        }
      })
      setItems(entries)
      await api.saveSettings({ ...settings, opdsCatalogs: [{ name: '当前目录', url: fetchUrl }] })
    } catch (cause) {
      toast.error(`加载目录失败：${String(cause)}`)
    } finally {
      setLoading(false)
    }
  }

  const handleDownloadAndImport = async (item: FeedItem) => {
    const targetUrl = item.acquisitionHref || item.href
    if (!targetUrl) return
    setImportingHref(targetUrl)
    try {
      const response = await fetch(targetUrl)
      if (!response.ok) throw new Error(`下载失败: HTTP ${response.status}`)
      const blob = await response.blob()
      const filename = `${item.title.replace(/[\\/:*?"<>|]/g, '_')}.epub`
      const file = new File([blob], filename, { type: 'application/epub+zip' })
      const source = new Uint8Array(await file.arrayBuffer())
      const prepared = prepareBookFile(file, source)

      await api.importBook({
        name: prepared.name,
        data: prepared.bytes,
        title: item.title || prepared.title,
        author: item.author || prepared.author,
        mediaType: prepared.mediaType,
        cover: prepared.cover,
      })
      toast.success(`已成功下载并导入《${item.title}》至书架`)
    } catch (e) {
      toast.error(`导入失败：${String(e)}`)
    } finally {
      setImportingHref(null)
    }
  }

  return (
    <main className="px-4 pt-4 pb-8 max-w-4xl mx-auto">
      <header className="mb-4 flex items-center justify-between gap-3">
        <div>
          <h1 className="font-heading text-2xl flex items-center gap-2">
            <Rss className="size-5 text-primary" />
            OPDS 书源
          </h1>
          <p className="text-xs text-muted-foreground mt-0.5">
            探索开放电子书目录，直接下载并导入本地书架
          </p>
        </div>
        <Button onClick={() => void load()} disabled={loading}>
          {loading ? <Loader2 className="size-4 animate-spin mr-1" /> : null}
          {loading ? '正在获取…' : '浏览书库'}
        </Button>
      </header>

      {/* Preset catalogs chips */}
      <div className="flex flex-wrap items-center gap-1.5 mb-3">
        <span className="text-xs text-muted-foreground mr-1">快捷书源:</span>
        {PRESET_CATALOGS.map((preset) => (
          <Button
            key={preset.name}
            type="button"
            size="xs"
            variant="outline"
            className="rounded-full text-xs"
            onClick={() => {
              setUrl(preset.url)
              void load(preset.url)
            }}
          >
            {preset.name}
          </Button>
        ))}
      </div>

      <div className="flex gap-2 mb-6">
        <Input
          className="font-mono text-xs"
          value={url}
          onChange={(event) => setUrl(event.target.value)}
          placeholder="https://example.com/opds/all"
          onKeyDown={(e) => {
            if (e.key === 'Enter') void load()
          }}
        />
      </div>

      {loading ? (
        <div className="flex flex-col items-center justify-center py-20 text-muted-foreground text-xs gap-2">
          <Loader2 className="size-6 animate-spin text-primary" />
          <span>正在连接并解析书库条目…</span>
        </div>
      ) : items.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 px-4 text-center">
          <div className="size-16 rounded-2xl bg-muted/60 flex items-center justify-center text-muted-foreground mb-4 shadow-inner">
            <Globe className="size-8 stroke-[1.5]" />
          </div>
          <h3 className="text-base font-semibold mb-1">尚未加载 OPDS 目录</h3>
          <p className="text-muted-foreground text-xs max-w-sm mb-4 leading-relaxed">
            点击上方快捷公共书源或输入自建 Calibre / Kavita 书库地址，点击「浏览书库」即可探索图书。
          </p>
        </div>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2">
          {items.map((item, idx) => {
            const isImporting = importingHref === (item.acquisitionHref || item.href)
            return (
              <Card
                key={`${item.title}-${idx}`}
                size="sm"
                className="flex flex-col justify-between hover:shadow-xs transition-shadow"
              >
                <CardHeader className="pb-2">
                  <CardTitle className="text-sm font-semibold line-clamp-1">
                    {item.title}
                  </CardTitle>
                  <p className="text-xs text-muted-foreground line-clamp-1">
                    {item.author || '未知作者'}
                  </p>
                </CardHeader>
                <CardContent className="space-y-3 pt-0">
                  {item.summary ? (
                    <p className="text-xs text-muted-foreground/80 line-clamp-2 leading-relaxed">
                      {item.summary}
                    </p>
                  ) : null}
                  <div className="flex items-center justify-end gap-2 border-t border-border/50 pt-2.5">
                    {item.acquisitionHref ? (
                      <Button
                        size="xs"
                        disabled={isImporting}
                        onClick={() => void handleDownloadAndImport(item)}
                      >
                        {isImporting ? (
                          <Loader2 className="size-3 animate-spin mr-1" />
                        ) : (
                          <BookDown className="size-3 mr-1" />
                        )}
                        {isImporting ? '导入中…' : '导入书架'}
                      </Button>
                    ) : item.href ? (
                      <Button size="xs" variant="outline" asChild>
                        <a href={item.href} target="_blank" rel="noreferrer">
                          <ExternalLink className="size-3 mr-1" />
                          打开链接
                        </a>
                      </Button>
                    ) : null}
                  </div>
                </CardContent>
              </Card>
            )
          })}
        </div>
      )}
    </main>
  )
}
