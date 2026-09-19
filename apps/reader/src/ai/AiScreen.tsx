import { useChat } from '@ai-sdk/react'
import {
  getToolName,
  isToolUIPart,
  lastAssistantMessageIsCompleteWithApprovalResponses,
  type DynamicToolUIPart,
  type ToolUIPart,
} from 'ai'
import { useEffect, useMemo, useRef, useState } from 'react'
import { api, isMobile, type Settings } from '../api'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { createLeeefTransport, type LeeefUIMessage } from './agent'
import { hasAiCredentials } from './provider'
import { TOOL_LABELS } from './tools'

const SUGGESTED_PROMPTS = [
  '我的书库里有哪些书？',
  '最近在读什么？',
  '帮我找相关书摘',
]

export function AiScreen() {
  const [settings, setSettings] = useState<Settings | null>(null)

  useEffect(() => {
    void api.getSettings().then(setSettings)
  }, [])

  if (settings == null) {
    return (
      <main className="px-4 pt-4 pb-4">
        <h1 className="font-heading mb-4 text-2xl">AI</h1>
        <p className="text-muted-foreground">正在读取设置…</p>
      </main>
    )
  }

  if (!hasAiCredentials(settings)) {
    return (
      <main className="px-4 pt-4 pb-4">
        <h1 className="font-heading mb-4 text-2xl">AI</h1>
        <p className="text-muted-foreground">
          {isMobile()
            ? '请在桌面设置里填写 OpenAI 兼容 Endpoint 和 API Key，再通过配对同步到手机。'
            : '请在设置里填写 OpenAI 兼容 Endpoint 和 API Key。'}
        </p>
      </main>
    )
  }

  return <AiChat settings={settings} />
}

function AiChat({ settings }: { settings: Settings }) {
  const [input, setInput] = useState('')
  const bottomRef = useRef<HTMLDivElement>(null)
  const transport = useMemo(
    () => createLeeefTransport(settings),
    [settings.aiEndpoint, settings.aiKey, settings.aiModel],
  )
  const { messages, sendMessage, status, stop, error, addToolApprovalResponse } =
    useChat<LeeefUIMessage>({
      transport,
      sendAutomaticallyWhen: lastAssistantMessageIsCompleteWithApprovalResponses,
    })
  const busy = status === 'submitted' || status === 'streaming'

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ block: 'end' })
  }, [messages, status])

  const submit = (text: string) => {
    const trimmed = text.trim()
    if (!trimmed || busy) return
    setInput('')
    void sendMessage({ text: trimmed })
  }

  return (
    <main className="flex h-full flex-col px-4 pt-4 pb-4">
      <h1 className="font-heading mb-4 text-2xl">AI</h1>
      <div className="mb-3 min-h-0 flex-1 space-y-3 overflow-auto">
        {messages.length === 0 ? (
          <div className="space-y-3">
            <p className="text-muted-foreground">问书库、进度或书摘。写操作会先请你确认。</p>
            <div className="flex flex-wrap gap-2">
              {SUGGESTED_PROMPTS.map((prompt) => (
                <Button
                  key={prompt}
                  type="button"
                  size="sm"
                  variant="outline"
                  onClick={() => submit(prompt)}
                >
                  {prompt}
                </Button>
              ))}
            </div>
          </div>
        ) : null}
        {messages.map((message) => (
          <article
            key={message.id}
            className={
              message.role === 'user'
                ? 'bg-secondary ml-8 rounded-lg px-3 py-2'
                : 'bg-card mr-8 space-y-2 rounded-lg px-3 py-2 ring-1 ring-foreground/10'
            }
          >
            {message.parts.map((part, index) => {
              if (part.type === 'text') {
                return (
                  <p key={index} className="whitespace-pre-wrap">
                    {part.text}
                  </p>
                )
              }
              if (part.type === 'reasoning') {
                return (
                  <p key={index} className="text-muted-foreground text-xs whitespace-pre-wrap">
                    {part.text}
                  </p>
                )
              }
              if (isToolUIPart(part)) {
                return (
                  <ToolCallCard
                    key={part.toolCallId}
                    part={part}
                    onApprove={(id) => addToolApprovalResponse({ id, approved: true })}
                    onDeny={(id) => addToolApprovalResponse({ id, approved: false })}
                  />
                )
              }
              return null
            })}
          </article>
        ))}
        {error ? <p className="text-destructive text-sm">{error.message}</p> : null}
        <div ref={bottomRef} />
      </div>
      <form
        className="flex gap-2"
        onSubmit={(event) => {
          event.preventDefault()
          submit(input)
        }}
      >
        <Input
          value={input}
          onChange={(event) => setInput(event.target.value)}
          placeholder="问书库或当前阅读"
          disabled={busy}
        />
        {busy ? (
          <Button type="button" variant="outline" onClick={() => stop()}>
            停止
          </Button>
        ) : (
          <Button type="submit">发送</Button>
        )}
      </form>
    </main>
  )
}

function ToolCallCard({
  part,
  onApprove,
  onDeny,
}: {
  part: ToolUIPart | DynamicToolUIPart
  onApprove: (id: string) => void
  onDeny: (id: string) => void
}) {
  const name = getToolName(part)
  const label = TOOL_LABELS[name] ?? name
  const waiting =
    part.state === 'approval-requested' && part.approval.isAutomatic !== true

  return (
    <div className="bg-muted/50 space-y-2 rounded-md px-2 py-2 text-sm">
      <div className="flex items-center gap-2">
        <Badge variant="outline">{label}</Badge>
        <span className="text-muted-foreground text-xs">{toolStateLabel(part)}</span>
      </div>
      {part.input != null ? (
        <pre className="text-muted-foreground overflow-x-auto text-xs whitespace-pre-wrap">
          {formatJson(part.input)}
        </pre>
      ) : null}
      {part.state === 'output-available' ? (
        <pre className="overflow-x-auto text-xs whitespace-pre-wrap">{formatJson(part.output)}</pre>
      ) : null}
      {part.state === 'output-error' ? (
        <p className="text-destructive text-xs">{part.errorText}</p>
      ) : null}
      {part.state === 'output-denied' ? (
        <p className="text-muted-foreground text-xs">已拒绝{part.approval.reason ? `：${part.approval.reason}` : ''}</p>
      ) : null}
      {waiting ? (
        <div className="flex gap-2">
          <Button size="sm" onClick={() => onApprove(part.approval.id)}>
            允许
          </Button>
          <Button size="sm" variant="outline" onClick={() => onDeny(part.approval.id)}>
            拒绝
          </Button>
        </div>
      ) : null}
    </div>
  )
}

function toolStateLabel(part: ToolUIPart | DynamicToolUIPart): string {
  switch (part.state) {
    case 'input-streaming':
      return '准备中'
    case 'input-available':
      return '执行中'
    case 'approval-requested':
      return part.approval.isAutomatic ? '自动确认' : '等待确认'
    case 'approval-responded':
      return part.approval.approved ? '已允许' : '已拒绝'
    case 'output-available':
      return '完成'
    case 'output-error':
      return '失败'
    case 'output-denied':
      return '已拒绝'
  }
}

function formatJson(value: unknown): string {
  if (typeof value === 'string') return value
  try {
    return JSON.stringify(value, null, 2)
  } catch {
    return String(value)
  }
}
