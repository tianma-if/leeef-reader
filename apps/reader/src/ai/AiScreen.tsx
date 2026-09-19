import { useEffect, useState } from 'react'
import { api, type Book, type Settings } from '../api'

type Msg = { role: 'user' | 'assistant'; content: string }

export function AiScreen() {
  const [settings, setSettings] = useState<Settings>({})
  const [books, setBooks] = useState<Book[]>([])
  const [input, setInput] = useState('')
  const [messages, setMessages] = useState<Msg[]>([])
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    void api.getSettings().then(setSettings)
    void api.listBooks().then(setBooks)
  }, [])

  const send = async () => {
    if (!input.trim() || busy) return
    const history = [...messages, { role: 'user' as const, content: input.trim() }]
    setMessages(history)
    setInput('')
    if (!settings.aiEndpoint || !settings.aiKey) {
      setMessages([
        ...history,
        {
          role: 'assistant',
          content: `当前书库 ${books.length} 本。请在桌面设置里填写 OpenAI 兼容 Endpoint 和 API Key。`,
        },
      ])
      return
    }
    setBusy(true)
    try {
      const response = await fetch(`${settings.aiEndpoint.replace(/\/$/, '')}/chat/completions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${settings.aiKey}`,
        },
        body: JSON.stringify({
          model: settings.aiModel || 'gpt-4o-mini',
          messages: [
            {
              role: 'system',
              content: `你是 Leeef Reader 助手。书库：${books.map((book) => book.title).join('、')}`,
            },
            ...history,
          ],
        }),
      })
      const json = (await response.json()) as {
        choices?: { message?: { content?: string } }[]
      }
      setMessages([
        ...history,
        { role: 'assistant', content: json.choices?.[0]?.message?.content ?? '没有返回内容' },
      ])
    } catch (cause) {
      setMessages([...history, { role: 'assistant', content: String(cause) }])
    } finally {
      setBusy(false)
    }
  }

  return (
    <main className="page">
      <header className="page-bar">
        <h1>AI</h1>
      </header>
      <div className="chat">
        {messages.map((message, index) => (
          <p key={index} className={message.role}>
            {message.content}
          </p>
        ))}
      </div>
      <form
        className="row"
        onSubmit={(event) => {
          event.preventDefault()
          void send()
        }}
      >
        <input
          value={input}
          onChange={(event) => setInput(event.target.value)}
          placeholder="问书库或当前阅读"
        />
        <button type="submit" className="btn" disabled={busy}>
          发送
        </button>
      </form>
    </main>
  )
}
