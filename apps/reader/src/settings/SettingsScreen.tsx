import { useEffect, useState } from 'react'
import { listen, type UnlistenFn } from '@tauri-apps/api/event'
import { toast } from 'sonner'
import { api, type PairingOffer, type Settings, type SettingsSyncStatus } from '../api'
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
import { FontPicker } from '../reader/FontPicker'

const desktop = !/Android|iPhone|iPad/i.test(navigator.userAgent)

export function SettingsScreen() {
  const [value, setValue] = useState<Settings>({})
  const [dbPath, setDbPath] = useState('')
  const [mcp, setMcp] = useState<{
    running: boolean
    endpoint?: string
    token?: string
  }>({ running: false })
  const [pair, setPair] = useState<PairingOffer | null>(null)
  const [pairCode, setPairCode] = useState('')
  const [pairBusy, setPairBusy] = useState(false)
  const [syncStatus, setSyncStatus] = useState<SettingsSyncStatus | null>(null)
  const [edgeEverBusy, setEdgeEverBusy] = useState(false)
  const [edgeEverNotebooks, setEdgeEverNotebooks] = useState<{ id: string; name: string }[]>([])

  useEffect(() => {
    void api.getSettings().then((settings) => {
      setValue(settings)
      if (settings.edgeEverEnabled) {
        void api.edgeEverNotebooks().then(setEdgeEverNotebooks).catch(() => undefined)
      }
    })
    void api.mcpDatabasePath().then(setDbPath)
    void api.mcpStatus().then(setMcp).catch(() => undefined)
    void api.settingsSyncStatus().then(setSyncStatus).catch(() => undefined)
    let unlistenStatus: UnlistenFn | undefined
    let unlistenSettings: UnlistenFn | undefined
    void listen<SettingsSyncStatus>('settings-sync-status', (event) => {
      setSyncStatus(event.payload)
    }).then((stop) => { unlistenStatus = stop })
    void listen('settings-synced', () => {
      void api.getSettings().then(setValue)
    }).then((stop) => { unlistenSettings = stop })
    return () => {
      unlistenStatus?.()
      unlistenSettings?.()
    }
  }, [])

  const patch = (next: Partial<Settings>) => setValue((current) => ({ ...current, ...next }))

  return (
    <main className="mx-auto max-w-xl px-4 pt-4 pb-8">
      <header className="mb-6 flex items-center justify-between gap-3">
        <h1 className="font-heading text-2xl">设置</h1>
        <Button
          onClick={() =>
            void api.saveSettings(value).then(() => toast.success('已保存，正在同步'))
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
          <Label>字体</Label>
          <FontPicker
            value={value.fontFamily}
            onChange={(fontFamily) => patch({ fontFamily })}
          />
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
              placeholder={value.syncBackend === 's3' ? 'https://s3.example.com' : 'https://dav.example.com/leeef'}
            />
          </div>
          {value.syncBackend === 'webdav' ? (
            <>
              <div className="grid gap-1.5">
                <Label>用户名</Label>
                <Input
                  value={value.syncUsername ?? ''}
                  onChange={(event) => patch({ syncUsername: event.target.value })}
                />
              </div>
              <div className="grid gap-1.5">
                <Label>密码</Label>
                <Input
                  type="password"
                  value={value.syncPassword ?? ''}
                  onChange={(event) => patch({ syncPassword: event.target.value })}
                />
              </div>
            </>
          ) : null}
          {value.syncBackend === 's3' ? (
            <>
              <div className="grid gap-1.5">
                <Label>Bucket</Label>
                <Input
                  value={value.syncBucket ?? ''}
                  onChange={(event) => patch({ syncBucket: event.target.value })}
                />
              </div>
              <div className="grid gap-1.5">
                <Label>Region</Label>
                <Input
                  value={value.syncRegion ?? 'us-east-1'}
                  onChange={(event) => patch({ syncRegion: event.target.value })}
                />
              </div>
              <div className="grid gap-1.5">
                <Label>Access Key</Label>
                <Input
                  value={value.syncAccessKey ?? ''}
                  onChange={(event) => patch({ syncAccessKey: event.target.value })}
                />
              </div>
              <div className="grid gap-1.5">
                <Label>Secret Key</Label>
                <Input
                  type="password"
                  value={value.syncSecretKey ?? ''}
                  onChange={(event) => patch({ syncSecretKey: event.target.value })}
                />
              </div>
              <div className="grid gap-1.5">
                <Label>对象前缀</Label>
                <Input
                  value={value.syncPrefix ?? 'leeef'}
                  onChange={(event) => patch({ syncPrefix: event.target.value })}
                />
              </div>
            </>
          ) : null}
          <p className="text-muted-foreground text-sm">
            手机首次配对后会持续同步这些配置；敏感值离开设备前会使用同步空间密钥加密。
          </p>

          <Separator className="my-2" />
          <h2 className="text-lg">EdgeEver 书摘同步</h2>
          <p className="text-muted-foreground text-sm">
            每本书固定同步为一篇 EdgeEver 笔记。Token 需要 read:notebooks、read:memos 和
            write:memos 权限。
          </p>
          <div className="grid gap-1.5">
            <Label>状态</Label>
            <Select
              value={value.edgeEverEnabled ? 'enabled' : 'disabled'}
              onValueChange={(state) => patch({ edgeEverEnabled: state === 'enabled' })}
            >
              <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="disabled">关闭</SelectItem>
                <SelectItem value="enabled">实时同步</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="grid gap-1.5">
            <Label>EdgeEver 实例地址</Label>
            <Input
              value={value.edgeEverEndpoint ?? ''}
              onChange={(event) => patch({ edgeEverEndpoint: event.target.value })}
              placeholder="https://notes.example.com"
            />
          </div>
          <div className="grid gap-1.5">
            <Label>API Token</Label>
            <Input
              type="password"
              value={value.edgeEverToken ?? ''}
              onChange={(event) => patch({ edgeEverToken: event.target.value })}
            />
          </div>
          <div className="grid gap-1.5">
            <Label>目标笔记本</Label>
            <Select
              value={value.edgeEverNotebookId || 'none'}
              onValueChange={(id) => patch({ edgeEverNotebookId: id === 'none' ? '' : id })}
            >
              <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="none">尚未选择</SelectItem>
                {edgeEverNotebooks.map((notebook) => (
                  <SelectItem key={notebook.id} value={notebook.id}>{notebook.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="flex flex-wrap gap-2">
            <Button
              variant="outline"
              disabled={edgeEverBusy}
              onClick={() => {
                setEdgeEverBusy(true)
                void api.saveSettings(value)
                  .then(() => Promise.all([api.edgeEverTest(), api.edgeEverNotebooks()]))
                  .then(([result, notebooks]) => {
                    setEdgeEverNotebooks(notebooks)
                    toast.success(result.message)
                  })
                  .catch((cause) => toast.error(String(cause)))
                  .finally(() => setEdgeEverBusy(false))
              }}
            >
              测试连接并加载笔记本
            </Button>
            <Button
              variant="outline"
              disabled={edgeEverBusy || !value.edgeEverNotebookId}
              onClick={() => {
                setEdgeEverBusy(true)
                void api.saveSettings(value)
                  .then(() => api.edgeEverSyncAll())
                  .then((result) => {
                    if (result.failed) toast.error(result.errors.join('\n'))
                    else toast.success(`已同步 ${result.synced} 本，跳过 ${result.skipped} 本`)
                  })
                  .catch((cause) => toast.error(String(cause)))
                  .finally(() => setEdgeEverBusy(false))
              }}
            >
              立即同步全部书摘
            </Button>
          </div>
        </section>
      ) : (
        <p className="text-muted-foreground text-sm">
          对象存储、AI 和 TTS 凭据只在桌面端填写，手机通过配对同步。
        </p>
      )}

      <Separator className="my-6" />
      <section className="grid gap-3">
        <h2 className="text-lg">设备与配置同步</h2>
        <div className="grid gap-1.5">
          <Label>自动同步</Label>
          <Select
            value={(value.autoSync ?? true) ? 'enabled' : 'disabled'}
            onValueChange={(next) => patch({ autoSync: next === 'enabled' })}
          >
            <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="enabled">开启</SelectItem>
              <SelectItem value="disabled">关闭（仅手动同步）</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <p className="text-muted-foreground text-sm">
          {syncStatus?.paired
            ? syncStatus.lastError
              ? `已配对；上次同步失败：${syncStatus.lastError}`
              : syncStatus.lastSuccessAt
                ? `已配对；最近同步 ${new Date(syncStatus.lastSuccessAt).toLocaleString()}`
                : '已配对，等待首次云端同步'
            : '尚未加入同步空间'}
        </p>
        {desktop ? (
          <div className="flex flex-wrap items-center gap-3">
            <Button
              variant="outline"
              disabled={pairBusy}
              onClick={() => {
                setPairBusy(true)
                void api.pairingStart()
                  .then(setPair)
                  .catch((cause) => toast.error(String(cause)))
                  .finally(() => setPairBusy(false))
              }}
            >
              生成配对码
            </Button>
            {pair ? (
              <strong className="font-mono tracking-[0.18em]">{pair.code}</strong>
            ) : null}
          </div>
        ) : (
          <div className="flex items-end gap-2">
            <div className="grid flex-1 gap-1.5">
              <Label>桌面端配对码</Label>
              <Input
                value={pairCode}
                maxLength={12}
                autoCapitalize="characters"
                className="font-mono uppercase tracking-widest"
                onChange={(event) => setPairCode(event.target.value.toUpperCase())}
              />
            </div>
            <Button
              disabled={pairBusy || pairCode.trim().length !== 12}
              onClick={() => {
                setPairBusy(true)
                void api.pairingJoin(pairCode)
                  .then(async (status) => {
                    setSyncStatus(status)
                    setValue(await api.getSettings())
                    toast.success('配对成功，配置会继续自动同步')
                  })
                  .catch((cause) => toast.error(String(cause)))
                  .finally(() => setPairBusy(false))
              }}
            >
              配对
            </Button>
          </div>
        )}
        {syncStatus?.paired ? (
          <Button
            variant="outline"
            disabled={syncStatus.running}
            onClick={() => {
              void api.settingsSyncNow()
                .then((status) => {
                  setSyncStatus(status)
                  toast.success(status.appliedValues ? `已应用 ${status.appliedValues} 项配置` : '配置已是最新')
                })
                .catch((cause) => toast.error(String(cause)))
            }}
          >
            立即同步配置
          </Button>
        ) : null}
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
