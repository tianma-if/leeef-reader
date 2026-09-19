import { useEffect, useState } from 'react'
import { toast } from 'sonner'
import { api, type Settings } from '../api'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Separator } from '@/components/ui/separator'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Slider } from '@/components/ui/slider'

const desktop = !/Android|iPhone|iPad/i.test(navigator.userAgent)

export function SettingsScreen() {
  const [value, setValue] = useState<Settings>({})
  const [dbPath, setDbPath] = useState('')
  const [mcp, setMcp] = useState<{
    running: boolean
    endpoint?: string
    token?: string
  }>({ running: false })
  const [pair, setPair] = useState('')

  useEffect(() => {
    void api.getSettings().then(setValue)
    void api.mcpDatabasePath().then(setDbPath)
    void api.mcpStatus().then(setMcp).catch(() => undefined)
  }, [])

  const patch = (next: Partial<Settings>) => setValue((current) => ({ ...current, ...next }))

  return (
    <main className="mx-auto max-w-xl px-4 pt-[calc(1rem+env(safe-area-inset-top,0px))] pb-8">
      <header className="mb-6 flex items-center justify-between gap-3">
        <h1 className="font-heading text-2xl">设置</h1>
        <Button
          onClick={() =>
            void api.saveSettings(value).then(() => toast.success('已保存'))
          }
        >
          保存
        </Button>
      </header>

      <section className="grid gap-4">
        <h2 className="text-lg">阅读外观</h2>
        <div className="grid gap-1.5">
          <Label>主题</Label>
          <Select
            value={value.theme ?? 'paper'}
            onValueChange={(theme) => patch({ theme: theme as Settings['theme'] })}
          >
            <SelectTrigger className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="paper">纸张</SelectItem>
              <SelectItem value="sepia">护眼</SelectItem>
              <SelectItem value="night">夜间</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="grid gap-2">
          <Label>字号 {value.fontSize ?? 18}</Label>
          <Slider
            min={14}
            max={28}
            value={[value.fontSize ?? 18]}
            onValueChange={([fontSize]) => patch({ fontSize })}
          />
        </div>
        <div className="grid gap-2">
          <Label>行距 {value.lineHeight ?? 1.65}</Label>
          <Slider
            min={1.3}
            max={2.2}
            step={0.05}
            value={[value.lineHeight ?? 1.65]}
            onValueChange={([lineHeight]) => patch({ lineHeight })}
          />
        </div>
        <div className="grid gap-1.5">
          <Label>排版</Label>
          <Select
            value={value.flow ?? 'paginated'}
            onValueChange={(flow) => patch({ flow: flow as Settings['flow'] })}
          >
            <SelectTrigger className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="paginated">分页</SelectItem>
              <SelectItem value="scrolled">连续滚动</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="grid gap-1.5">
          <Label>栏数</Label>
          <Select
            value={String(value.columns ?? 1)}
            onValueChange={(columns) => patch({ columns: Number(columns) as 1 | 2 })}
          >
            <SelectTrigger className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="1">单栏</SelectItem>
              <SelectItem value="2">双栏</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="grid gap-1.5">
          <Label>中文</Label>
          <Select
            value={value.chinese ?? 'original'}
            onValueChange={(chinese) => patch({ chinese: chinese as Settings['chinese'] })}
          >
            <SelectTrigger className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="original">原文</SelectItem>
              <SelectItem value="simplified">简体</SelectItem>
              <SelectItem value="traditional">繁体</SelectItem>
            </SelectContent>
          </Select>
        </div>
      </section>

      <Separator className="my-6" />
      <section className="grid gap-4">
        <h2 className="text-lg">TTS</h2>
        <div className="grid gap-2">
          <Label>语速 {value.ttsRate ?? 1}</Label>
          <Slider
            min={0.6}
            max={1.6}
            step={0.1}
            value={[value.ttsRate ?? 1]}
            onValueChange={([ttsRate]) => patch({ ttsRate })}
          />
        </div>
      </section>

      <Separator className="my-6" />
      {desktop ? (
        <section className="grid gap-4">
          <h2 className="text-lg">AI（仅桌面填写）</h2>
          <p className="text-muted-foreground text-sm">
            OpenAI 兼容接口，DeepSeek、OpenRouter、xAI 等填各自 Base URL 即可。
          </p>
          <div className="grid gap-1.5">
            <Label>Endpoint</Label>
            <Input
              value={value.aiEndpoint ?? ''}
              onChange={(event) => patch({ aiEndpoint: event.target.value })}
              placeholder="https://api.openai.com/v1"
            />
          </div>
          <div className="grid gap-1.5">
            <Label>API Key</Label>
            <Input
              type="password"
              value={value.aiKey ?? ''}
              onChange={(event) => patch({ aiKey: event.target.value })}
            />
          </div>
          <div className="grid gap-1.5">
            <Label>模型</Label>
            <Input
              value={value.aiModel ?? ''}
              onChange={(event) => patch({ aiModel: event.target.value })}
              placeholder="gpt-4o-mini"
            />
          </div>
          <h2 className="text-lg">同步</h2>
          <div className="grid gap-1.5">
            <Label>后端</Label>
            <Select
              value={value.syncBackend || 'none'}
              onValueChange={(syncBackend) =>
                patch({
                  syncBackend: (syncBackend === 'none' ? '' : syncBackend) as Settings['syncBackend'],
                })
              }
            >
              <SelectTrigger className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="none">未配置</SelectItem>
                <SelectItem value="s3">S3 兼容</SelectItem>
                <SelectItem value="webdav">WebDAV</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="grid gap-1.5">
            <Label>地址</Label>
            <Input
              value={value.syncEndpoint ?? ''}
              onChange={(event) => patch({ syncEndpoint: event.target.value })}
            />
          </div>
          <p className="text-muted-foreground text-sm">
            手机通过桌面配对码同步这些凭据。写操作会记入 sync_operations。
          </p>
        </section>
      ) : (
        <p className="text-muted-foreground text-sm">
          对象存储、AI 和 TTS 凭据只在桌面端填写，手机通过配对同步。
        </p>
      )}

      <Separator className="my-6" />
      <section className="grid gap-3">
        <h2 className="text-lg">配对</h2>
        <div className="flex items-center gap-3">
          <Button variant="outline" onClick={() => void api.pairingCode().then(setPair)}>
            生成配对码
          </Button>
          {pair ? <strong className="tracking-widest">{pair}</strong> : null}
        </div>
      </section>

      <Separator className="my-6" />
      <section className="grid gap-3">
        <h2 className="text-lg">MCP</h2>
        <p className="text-muted-foreground text-sm">数据库：{dbPath || '…'}</p>
        <p className="text-muted-foreground text-sm">
          {mcp.running ? `已运行 ${mcp.endpoint}` : '未运行'}
        </p>
        {mcp.running && mcp.token ? (
          <p className="text-muted-foreground break-all font-mono text-xs">Bearer {mcp.token}</p>
        ) : null}
        <div className="flex gap-2">
          <Button
            onClick={() =>
              void api.mcpStart().then(setMcp).catch((cause) => toast.error(String(cause)))
            }
          >
            启动 MCP
          </Button>
          <Button variant="outline" onClick={() => void api.mcpStop().then(setMcp)}>
            停止
          </Button>
        </div>
      </section>
    </main>
  )
}
