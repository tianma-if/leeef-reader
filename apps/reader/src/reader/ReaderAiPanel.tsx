import { useChat } from '@ai-sdk/react'
import { useEffect, useMemo, useState } from 'react'
import ReactMarkdown from 'react-markdown'
import { toast } from 'sonner'
import { api, type Settings } from '../api'
import { hasAiCredentials } from '../ai/provider'
import { loadSelectionHistory, saveSelectionHistory, selectionHistoryKey } from '../ai/selectionHistory'
import { conversationNote, selectionTransport, type ReadingSource, type SelectionMessage } from '../ai/selectionAgent'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from '@/components/ui/sheet'

type Props = {
  bookId: string
  source: ReadingSource
  settings: Settings
  onClose: () => void
  onGo: (locator: string) => void
  onSaved: () => Promise<void>
}

export function ReaderAiPanel(props: Props) {
  return (
    <Sheet open onOpenChange={(open) => { if (!open) props.onClose() }}>
      <SheetContent className="data-[side=right]:w-full data-[side=right]:sm:max-w-lg" side="right">
        <SheetHeader>
          <SheetTitle>阅读助手</SheetTitle>
          <SheetDescription>{props.source.bookTitle} · {props.source.chapter || '选中原文'}</SheetDescription>
        </SheetHeader>
        {hasAiCredentials(props.settings) ? <SelectionChat {...props} /> : (
          <p className="px-4 text-sm text-muted-foreground">请先在桌面设置中配置 AI，手机可以通过设备配对获取配置。关闭此面板可继续阅读。</p>
        )}
      </SheetContent>
    </Sheet>
  )
}

function SelectionChat({ bookId, source, settings, onGo, onSaved }: Props) {
  const [input, setInput] = useState('')
  const [saving, setSaving] = useState(false)
  const [savedSignature, setSavedSignature] = useState('')
  const historyKey = selectionHistoryKey(bookId, source.locator)
  const [history] = useState(() => loadSelectionHistory(localStorage, historyKey))
  const transport = useMemo(() => selectionTransport(settings, source), [settings.aiEndpoint, settings.aiKey, settings.aiModel, source])
  const { messages, sendMessage, status, stop, error, regenerate } = useChat<SelectionMessage>({ transport, messages: history })
  const busy = status === 'submitted' || status === 'streaming'
  useEffect(() => {
    if (busy) return
    try { saveSelectionHistory(localStorage, historyKey, messages) }
    catch { toast.error('本机对话存储已满，请将重要回答保存为笔记') }
  }, [busy, historyKey, messages])
  const hasAnswer = messages.some((message) => message.role === 'assistant' && message.parts.some((part) => part.type === 'text' && part.text.trim()))
  const signature = conversationNote(messages)
  const submit = (text: string) => {
    if (!text.trim() || busy) return
    setInput('')
    void sendMessage({ text: text.trim() })
  }
  const visitSource = () => onGo(source.locator)

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3 px-4 pb-4">
      <div className="rounded-lg border p-3 text-xs">
        <blockquote className="max-h-32 overflow-y-auto whitespace-pre-wrap">{source.quote}</blockquote>
        <Button size="xs" variant="link" onClick={visitSource}>回到原文</Button>
      </div>
      <p className="text-xs text-muted-foreground">仅将选中原文与本次对话发送给已配置的 AI 服务。对话保存在本机，重新选中同一段落可继续；保存为笔记后可随书库同步。</p>
      <div className="flex flex-wrap gap-2">
        <Button size="sm" variant="outline" disabled={busy} onClick={() => submit('请解释这段原文的含义，并引用原文。')}>解释</Button>
        <Button size="sm" variant="outline" disabled={busy} onClick={() => submit('请将这段原文翻译成中文；若原文已经是中文，则翻译成英文。请保留原意。')}>翻译</Button>
        <Button size="sm" variant="outline" disabled={busy} onClick={() => submit('请概括这段原文的要点，明确区分原文与推断。')}>概括</Button>
      </div>
      <div className="min-h-0 flex-1 space-y-3 overflow-y-auto" aria-label="阅读对话">
        {messages.map((message) => (
          <article key={message.id} className="rounded-lg border p-3 text-sm break-words [&_ul]:list-disc [&_ul]:pl-4 [&_ol]:list-decimal [&_ol]:pl-4 [&_p]:my-1">
            <p className="mb-1 text-xs text-muted-foreground">{message.role === 'user' ? '你' : 'AI'}</p>
            {message.parts.map((part, index) => part.type === 'text' ? (
              <ReactMarkdown key={index} components={{ img: ({ alt }) => <span>{alt || '图片'}</span>, a: ({ href, children }) => href === '#source'
                ? <button className="text-primary underline" onClick={visitSource}>{children}</button>
                : <span>{children}</span> }}>{part.text}</ReactMarkdown>
            ) : null)}
          </article>
        ))}
        {error ? <div role="alert" className="text-sm text-destructive">
          {error.message}<Button size="sm" variant="outline" disabled={busy} onClick={() => void regenerate()}>重试</Button>
        </div> : null}
      </div>
      <form className="flex gap-2" onSubmit={(event) => { event.preventDefault(); submit(input) }}>
        <Input aria-label="追问选中原文" value={input} disabled={busy} onChange={(event) => setInput(event.target.value)} placeholder="继续追问这段原文…" />
        {busy ? <Button type="button" variant="outline" onClick={() => void stop()}>停止</Button>
          : <Button type="submit" disabled={!input.trim()}>发送</Button>}
      </form>
      <Button variant="outline" disabled={busy || saving || !hasAnswer || savedSignature === signature}
        onClick={() => {
          setSaving(true)
          void api.createExcerpt({ bookId, locator: source.locator, quote: source.quote, note: signature, color: '#488bc2' })
            .then(async () => { setSavedSignature(signature); toast.success('对话已保存到书摘笔记'); await onSaved() })
            .catch((cause) => toast.error(String(cause))).finally(() => setSaving(false))
        }}>{saving ? '保存中…' : savedSignature === signature ? '已保存为笔记' : '将对话保存为笔记'}</Button>
    </div>
  )
}
