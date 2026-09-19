import { useEffect, useState } from 'react'
import { api, type Settings } from '../api'

type FeedItem = { title: string; href?: string; author?: string }

export function OpdsScreen() {
  const [settings, setSettings] = useState<Settings>({})
  const [url, setUrl] = useState('https://opds.feedbooks.net/catalog.atom')
  const [items, setItems] = useState<FeedItem[]>([])
  const [error, setError] = useState('')

  useEffect(() => {
    void api.getSettings().then((value) => {
      setSettings(value)
      if (value.opdsCatalogs?.[0]?.url) setUrl(value.opdsCatalogs[0].url)
    })
  }, [])

  const load = async () => {
    setError('')
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
      const catalogs = [{ name: '当前目录', url }]
      await api.saveSettings({ ...settings, opdsCatalogs: catalogs })
    } catch (cause) {
      setError(String(cause))
    }
  }

  return (
    <main className="page">
      <header className="page-bar">
        <h1>OPDS</h1>
        <button type="button" className="btn" onClick={() => void load()}>
          浏览
        </button>
      </header>
      <input value={url} onChange={(event) => setUrl(event.target.value)} />
      {error ? <p className="reader-error">{error}</p> : null}
      <ul className="plain">
        {items.map((item) => (
          <li key={`${item.title}-${item.href}`}>
            <strong>{item.title}</strong>
            {item.author ? <span> · {item.author}</span> : null}
            {item.href ? (
              <a href={item.href} target="_blank" rel="noreferrer">
                打开
              </a>
            ) : null}
          </li>
        ))}
      </ul>
    </main>
  )
}
