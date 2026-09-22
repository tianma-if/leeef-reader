import { useChat } from '@ai-sdk/react'
import { listen } from '@tauri-apps/api/event'
import {
  getToolName,
  isToolUIPart,
  lastAssistantMessageIsCompleteWithApprovalResponses,
  type DynamicToolUIPart,
  type ToolUIPart,
} from 'ai'
import { useEffect, useMemo, useRef, useState } from 'react'
import { Bot, Send, Sparkles, StopCircle } from 'lucide-react'
import ReactMarkdown from 'react-markdown'
import { api, isMobile, type Settings } from '../api'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { createLeeefTransport, type LeeefUIMessage } from './agent'
import { hasAiCredentials } from './provider'
import { TOOL_LABELS } from './tools'

const SUGGESTED_PROMPTS = [
  '我的书库里有哪些书？',
  '最近在读什么进度？',
  '帮我找与“思考”相关的书摘',
]

type AiScreenProps = {
  onNavigateToSettings?: () => void
}

export function AiScreen({ onNavigateToSettings }: AiScreenProps) {
  const [settings, setSettings] = useState<Settings | null>(null)

  useEffect(() => {
    void api.getSettings().then(setSettings)
    let stop: (() => void) | undefined
    void listen('settings-synced', () => {
      void api.getSettings().then(setSettings)
    }).then((unlisten) => {
      stop = unlisten
    })
    return () => stop?.()
  }, [])

  if (settings == null) {
    return (
      <main className="px-4 pt-4 pb-4 max-w-3xl mx-auto">
        <h1 className="font-heading mb-4 text-2xl">AI 助手</h1>
        <p className="text-muted-foreground text-sm">正在读取配置…</p>
      </main>
    )
  }

  if (!hasAiCredentials(settings)) {
    return (
      <main className="flex h-full flex-col items-center justify-center px-4 py-16 text-center max-w-md mx-auto">
        <div className="size-16 rounded-2xl bg-muted/60 flex items-center justify-center text-muted-foreground mb-4 shadow-inner">
          <Bot className="size-8 stroke-[1.5]" />
        </div>
        <h2 className="font-heading text-lg font-semibold mb-2">未配置 AI 凭据</h2>
        <p className="text-muted-foreground text-xs leading-relaxed mb-6">
          {isMobile()
            ? '请在桌面设置里填写 OpenAI 兼容 Endpoint 和 API Key，再通过配对同步到手机。'
            : '请在设置里填写 OpenAI 兼容 Endpoint 和 API Key。支持 DeepSeek、OpenRouter、ChatGPT 等各类模型。'}
        </p>
        {onNavigateToSettings ? (
          <Button onClick={onNavigateToSettings}>前往设置配置</Button>
        ) : null}
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
    <main className="flex h-full flex-col px-4 pt-4 pb-4 max-w-3xl mx-auto">
      <header className="mb-3 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Sparkles className="size-5 text-primary" />
          <h1 className="font-heading text-2xl">AI 助手</h1>
        </div>
        {settings.aiModel ? (
          <Badge variant="outline" className="text-xs font-mono">
            {settings.aiModel}
          </Badge>
        ) : null}
      </header>

      <div className="mb-3 min-h-0 flex-1 space-y-4 overflow-y-auto pr-1">
        {messages.length === 0 ? (
          <div className="space-y-4 py-8">
            <div className="text-center space-y-1.5">
              <p className="text-sm font-medium">随时提问你的书库与笔记</p>
              <p className="text-xs text-muted-foreground">
                支持检索书籍、查询进度、总结书摘。写操作会先向你请求确认。
              </p>
            </div>
            <div className="flex flex-wrap justify-center gap-2 pt-2">
              {SUGGESTED_PROMPTS.map((prompt) => (
                <Button
                  key={prompt}
                  type="button"
                  size="sm"
                  variant="outline"
                  className="rounded-full text-xs"
                  onClick={() => submit(prompt)}
                >
                  {prompt}
                </Button>
              ))}
            </div>
          </div>
        ) : null}

        {messages.map((message, msgIdx) => {
          const isUser = message.role === 'user'
          const isLastAssistant =
            !isUser && msgIdx === messages.length - 1 && busy

          return (
            <article
              key={message.id}
              className={`flex flex-col ${isUser ? 'items-end' : 'items-start'}`}
            >
              <div
                className={`max-w-[88%] rounded-2xl px-4 py-3 text-sm shadow-xs ${
                  isUser
                    ? 'bg-primary text-primary-foreground rounded-br-xs'
                    : 'bg-card border border-border/80 text-card-foreground rounded-bl-xs space-y-2'
                }`}
              >
                {message.parts.map((part, index) => {
                  if (part.type === 'text') {
                    if (isUser) {
                      return (
                        <p key={index} className="whitespace-pre-wrap leading-relaxed">
                          {part.text}
                        </p>
                      )
                    }
                    return (
                      <div
                        key={index}
                        className="prose prose-sm dark:prose-invert max-w-none break-words text-sm leading-relaxed space-y-2 [&_p]:my-1.5 [&_ul]:list-disc [&_ul]:pl-4 [&_ol]:list-decimal [&_ol]:pl-4 [&_code]:bg-muted [&_code]:px-1 [&_code]:py-0.5 [&_code]:rounded [&_code]:text-xs [&_pre]:bg-muted [&_pre]:p-2.5 [&_pre]:rounded-lg [&_pre]:overflow-x-auto [&_blockquote]:border-l-2 [&_blockquote]:border-primary/60 [&_blockquote]:pl-3 [&_blockquote]:text-muted-foreground"
                      >
                        <ReactMarkdown>{part.text}</ReactMarkdown>
                        {isLastAssistant && (
                          <span className="inline-block size-1.5 rounded-full bg-primary animate-ping ml-1" />
                        )}
                      </div>
                    )
                  }
                  if (part.type === 'reasoning') {
                    return (
                      <div
                        key={index}
                        className="bg-muted/50 rounded-md p-2 text-xs text-muted-foreground font-mono leading-relaxed"
                      >
                        <span className="font-semibold block mb-0.5">思考过程：</span>
                        {part.text}
                      </div>
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
              </div>
            </article>
          )
        })}

        {error ? (
          <div className="rounded-lg bg-destructive/10 p-3 text-destructive text-xs">
            {error.message}
          </div>
        ) : null}

        <div ref={bottomRef} />
      </div>

      <form
        className="flex gap-2 pt-2 border-t border-border/60"
        onSubmit={(event) => {
          event.preventDefault()
          submit(input)
        }}
      >
        <Input
          value={input}
          onChange={(event) => setInput(event.target.value)}
          placeholder="问书库、阅读进度或总结书摘…"
          disabled={busy}
          className="rounded-full px-4"
        />
        {busy ? (
          <Button
            type="button"
            variant="outline"
            size="icon"
            className="rounded-full shrink-0"
            onClick={() => stop()}
            title="停止生成"
          >
            <StopCircle className="size-4 text-destructive" />
          </Button>
        ) : (
          <Button
            type="submit"
            size="icon"
            className="rounded-full shrink-0"
            disabled={!input.trim()}
            title="发送"
          >
            <Send className="size-4" />
          </Button>
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
    <div className="bg-muted/60 space-y-2 rounded-lg p-2.5 text-xs border border-border/50">
      <div className="flex items-center justify-between gap-2">
        <Badge variant="outline" className="text-[11px] font-medium">
          {label}
        </Badge>
        <span className="text-muted-foreground text-[10px]">{toolStateLabel(part)}</span>
      </div>
      {part.input != null ? (
        <pre className="text-muted-foreground overflow-x-auto text-[11px] whitespace-pre-wrap font-mono bg-background/50 p-1.5 rounded">
          {formatJson(part.input)}
        </pre>
      ) : null}
      {part.state === 'output-available' ? (
        <pre className="overflow-x-auto text-[11px] whitespace-pre-wrap font-mono bg-background/50 p-1.5 rounded">
          {formatJson(part.output)}
        </pre>
      ) : null}
      {part.state === 'output-error' ? (
        <p className="text-destructive text-xs">{part.errorText}</p>
      ) : null}
      {part.state === 'output-denied' ? (
        <p className="text-muted-foreground text-xs">
          已拒绝{part.approval.reason ? `：${part.approval.reason}` : ''}
        </p>
      ) : null}
      {waiting ? (
        <div className="flex gap-2 pt-1">
          <Button size="xs" onClick={() => onApprove(part.approval.id)}>
            允许执行
          </Button>
          <Button size="xs" variant="outline" onClick={() => onDeny(part.approval.id)}>
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
      return part.approval.isAutomatic ? '自动确认' : '等待用户确认'
    case 'approval-responded':
      return part.approval.approved ? '已允许' : '已拒绝'
    case 'output-available':
      return '已完成'
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
