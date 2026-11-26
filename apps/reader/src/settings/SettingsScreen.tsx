import { useEffect, useRef, useState } from 'react'
import { listen, type UnlistenFn } from '@tauri-apps/api/event'
import {
  Bot,
  Cloud,
  Database,
  Eye,
  EyeOff,
  KeyRound,
  NotebookPen,
  Palette,
  Save,
  Share2,
  Volume2,
  Wifi,
} from 'lucide-react'
import { useTheme } from 'next-themes'
import { toast } from 'sonner'
import { api, type EdgeEverNotebook, type PairingOffer, type Settings, type SettingsSyncStatus } from '../api'
import { prepareEdgeEverExcerptChapters } from '../reader/excerptChapters'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Slider } from '@/components/ui/slider'
import { Textarea } from '@/components/ui/textarea'
import { FontPicker } from '../reader/FontPicker'
import { THEMES } from '../reader/bookStyles'
import { LibraryBackup } from './LibraryBackup'
import { SyncCenter } from './SyncCenter'
import { SettingChoices, SettingSwitch } from './SettingControls'
import { EdgeEverStatusCard } from './EdgeEverStatusCard'

const desktop = !/Android|iPhone|iPad/i.test(navigator.userAgent)

function PasswordInput({
  value,
  onChange,
  placeholder,
  ...props
}: {
  value: string
  onChange: (event: React.ChangeEvent<HTMLInputElement>) => void
  placeholder?: string
  [key: string]: any
}) {
  const [show, setShow] = useState(false)
  return (
    <div className="relative flex items-center">
      <Input
        type={show ? 'text' : 'password'}
        value={value}
        onChange={onChange}
        placeholder={placeholder}
        className="pr-9"
        {...props}
      />
      <button
        type="button"
        className="absolute right-2.5 text-muted-foreground hover:text-foreground p-0.5 rounded cursor-pointer"
        onClick={() => setShow((v) => !v)}
        title={show ? '隐藏内容' : '查看明文'}
      >
        {show ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
      </button>
    </div>
  )
}

export function SettingsScreen() {
  const { theme: appTheme, setTheme: setAppTheme } = useTheme()
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
  const [pairJoinError, setPairJoinError] = useState('')
  const [syncStatus, setSyncStatus] = useState<SettingsSyncStatus | null>(null)
  const [recoveryPassword, setRecoveryPassword] = useState('')
  const [recoveryPackage, setRecoveryPackage] = useState('')
  const [recoveryBusy, setRecoveryBusy] = useState(false)
  const recoveryFile = useRef<HTMLInputElement>(null)
  const [edgeEverBusy, setEdgeEverBusy] = useState(false)
  const [edgeEverNotebooks, setEdgeEverNotebooks] = useState<EdgeEverNotebook[]>([])

  // Modal dialog states
  const [joinConfirmOpen, setJoinConfirmOpen] = useState(false)
  const [recoveryConfirmOpen, setRecoveryConfirmOpen] = useState(false)

  useEffect(() => {
    void api.getSettings().then((settings) => {
      setValue(settings)
      if (desktop && settings.edgeEverEnabled) {
        void api.edgeEverNotebooks().then(setEdgeEverNotebooks).catch(() => undefined)
      }
    })
    void api.mcpDatabasePath().then(setDbPath)
    void api.mcpStatus().then(setMcp).catch(() => undefined)
    let disposed = false
    let statusEvents = 0
    let unlistenStatus: UnlistenFn | undefined
    let unlistenSettings: UnlistenFn | undefined
    void listen<SettingsSyncStatus>('settings-sync-status', (event) => {
      statusEvents++
      if (!disposed) setSyncStatus(event.payload)
    }).then((stop) => {
      if (disposed) { stop(); return }
      unlistenStatus = stop
      const observed = statusEvents
      void api.settingsSyncStatus().then((status) => {
        if (!disposed && observed === statusEvents) setSyncStatus(status)
      }).catch((cause) => toast.error(`无法读取同步状态：${String(cause)}`))
    }).catch((cause) => toast.error(`无法订阅同步状态：${String(cause)}`))
    void listen('settings-synced', () => {
      void api.getSettings().then(setValue)
    }).then((stop) => {
      if (disposed) stop()
      else unlistenSettings = stop
    })
    return () => {
      disposed = true
      unlistenStatus?.()
      unlistenSettings?.()
    }
  }, [])

  const patch = (next: Partial<Settings>) => setValue((current) => ({ ...current, ...next }))

  const handleSave = () => {
    void api.saveSettings(value).then(async () => {
      const status = await api.settingsSyncStatus()
      setSyncStatus(status)
      toast.success(status.autoSync && status.paired ? '设置已保存，正在同步' : '设置已保存')
    }).catch((cause) => toast.error(String(cause)))
  }

  const handleJoinExecute = () => {
    setJoinConfirmOpen(false)
    setPairJoinError('')
    setPairBusy(true)
    void api
      .pairingJoin(pairCode, Boolean(syncStatus?.paired))
      .then(async (status) => {
        setSyncStatus(status)
        setValue(await api.getSettings())
        toast.success('配对成功，配置会继续自动同步')
      })
      .catch((cause) => setPairJoinError(String(cause)))
      .finally(() => setPairBusy(false))
  }

  const handleRecoveryExecute = () => {
    setRecoveryConfirmOpen(false)
    setRecoveryBusy(true)
    void api
      .settingsRecoveryImport(recoveryPackage, recoveryPassword, Boolean(syncStatus?.paired))
      .then(async (status) => {
        let latest = status
        try {
          latest = await api.settingsSyncNow()
        } catch {
          // Local snapshot imported
        }
        setSyncStatus(latest)
        setValue(await api.getSettings())
        toast.success(
          latest.lastSuccessAt
            ? '恢复完成，已合并云端最新配置'
            : '恢复包已导入，联网后将继续同步',
        )
      })
      .catch((cause) => toast.error(String(cause)))
      .finally(() => setRecoveryBusy(false))
  }

  return (
    <main className="mx-auto max-w-2xl px-4 pt-4 pb-16 space-y-6">
      <header className="flex items-center justify-between gap-3 border-b pb-3">
        <div>
          <h1 className="font-heading text-2xl">设置</h1>
          <p className="text-xs text-muted-foreground mt-0.5">
            个性化阅读选项、存储后端与多端同步
          </p>
        </div>
        <Button onClick={handleSave}>
          <Save className="size-3.5 mr-1" />
          保存设置
        </Button>
      </header>

      {/* 1. 外观与阅读排版 */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <Palette className="size-4 text-primary" />
            界面与阅读外观
          </CardTitle>
          <CardDescription>配置应用程序界面模式与默认阅读版式</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <SettingChoices
            label="应用外观"
            value={appTheme ?? 'system'}
            onChange={setAppTheme}
            options={[
              { value: 'system', label: '跟随系统' },
              { value: 'light', label: '浅色' },
              { value: 'dark', label: '深色' },
            ]}
          />
          <SettingChoices
            label="阅读底色"
            value={value.theme ?? 'paper'}
            onChange={(theme) => patch({ theme })}
            options={[
              { value: 'paper', label: '纸张', swatch: THEMES.paper },
              { value: 'sepia', label: '护眼', swatch: THEMES.sepia },
              { value: 'night', label: '夜间', swatch: THEMES.night },
            ] as const}
          />

          <div className="grid gap-2">
            <Label>阅读字体</Label>
            <FontPicker
              value={value.fontFamily}
              onChange={(fontFamily) => patch({ fontFamily })}
            />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="grid gap-2">
              <div className="flex justify-between text-xs">
                <Label>字号</Label>
                <span className="font-mono text-muted-foreground">{value.fontSize ?? 18} px</span>
              </div>
              <Slider
                thumbLabel="字号"
                min={14}
                max={28}
                value={[value.fontSize ?? 18]}
                onValueChange={([fontSize]) => patch({ fontSize })}
              />
            </div>
            <div className="grid gap-2">
              <div className="flex justify-between text-xs">
                <Label>行距</Label>
                <span className="font-mono text-muted-foreground">{value.lineHeight ?? 1.65}</span>
              </div>
              <Slider
                thumbLabel="行距"
                min={1.3}
                max={2.2}
                step={0.05}
                value={[value.lineHeight ?? 1.65]}
                onValueChange={([lineHeight]) => patch({ lineHeight })}
              />
            </div>
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            <SettingChoices
              label="排版模式"
              value={value.flow ?? 'paginated'}
              onChange={(flow) => patch({ flow })}
              options={[
                { value: 'paginated', label: '左右分页' },
                { value: 'scrolled', label: '上下滚动' },
              ] as const}
            />
            <SettingChoices
              label="显示分栏"
              value={value.columns ?? 1}
              onChange={(columns) => patch({ columns })}
              options={[
                { value: 1, label: '单栏' },
                { value: 2, label: '双栏' },
              ] as const}
            />
          </div>
          <SettingChoices
            label="中文转换"
            value={value.chinese ?? 'original'}
            onChange={(chinese) => patch({ chinese })}
            options={[
              { value: 'original', label: '保持原文' },
              { value: 'simplified', label: '转为简体' },
              { value: 'traditional', label: '转为繁体' },
            ] as const}
          />
        </CardContent>
      </Card>

      {/* 2. TTS 朗读 */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <Volume2 className="size-4 text-primary" />
            语音朗读 (TTS)
          </CardTitle>
          <CardDescription>配置文本朗读的播放速率</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid gap-2">
            <div className="flex justify-between text-xs">
              <Label>语速倍率</Label>
              <span className="font-mono text-muted-foreground">{value.ttsRate ?? 1}x</span>
            </div>
            <Slider
              thumbLabel="语速倍率"
              min={0.6}
              max={1.6}
              step={0.1}
              value={[value.ttsRate ?? 1]}
              onValueChange={([ttsRate]) => patch({ ttsRate })}
            />
          </div>
        </CardContent>
      </Card>

      {/* 3. AI 大模型配置 */}
      {desktop ? (
        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2">
              <Bot className="size-4 text-primary" />
              AI 助手模型（仅桌面填写）
            </CardTitle>
            <CardDescription>
              支持 OpenAI 兼容 API，如 DeepSeek、OpenRouter、xAI 等，填入各自 Base URL 即可
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="grid gap-1.5">
              <Label>Endpoint 地址</Label>
              <Input
                value={value.aiEndpoint ?? ''}
                onChange={(event) => patch({ aiEndpoint: event.target.value })}
                placeholder="https://api.openai.com/v1"
              />
            </div>
            <div className="grid gap-1.5">
              <Label>API Key</Label>
              <PasswordInput
                value={value.aiKey ?? ''}
                onChange={(event: any) => patch({ aiKey: event.target.value })}
                placeholder="sk-..."
              />
            </div>
            <div className="grid gap-1.5">
              <Label>模型名称</Label>
              <Input
                value={value.aiModel ?? ''}
                onChange={(event) => patch({ aiModel: event.target.value })}
                placeholder="gpt-4o-mini 或 deepseek-chat"
              />
            </div>
          </CardContent>
        </Card>
      ) : (
        <div className="rounded-xl border border-dashed p-4 text-xs text-muted-foreground text-center">
          AI 与云存储敏感凭据在桌面端统一配置，手机端通过设备配对自动同步。
        </div>
      )}

      {/* 4. 数据存储与同步 */}
      {desktop ? (
        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2">
              <Cloud className="size-4 text-primary" />
              云端存储与多端同步后端
            </CardTitle>
            <CardDescription>
              配置 S3 兼容对象存储或 WebDAV 空间，同步阅读设置与服务配置；开启书库同步后，还会同步书籍、进度、书摘和分类
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <SettingChoices
              label="存储协议"
              value={value.syncBackend ?? ''}
              onChange={(syncBackend) => patch({ syncBackend })}
              options={[
                { value: '', label: '未配置' },
                { value: 's3', label: 'S3 兼容存储' },
                { value: 'webdav', label: 'WebDAV' },
              ] as const}
            />
            {value.syncBackend ? (
              <div className="grid gap-1.5">
                <Label htmlFor="sync-endpoint">服务端地址 (Endpoint)</Label>
                <Input
                  id="sync-endpoint"
                  type="url"
                  value={value.syncEndpoint ?? ''}
                  onChange={(event) => patch({ syncEndpoint: event.target.value })}
                  placeholder={
                    value.syncBackend === 's3'
                      ? 'https://s3.example.com'
                      : 'https://dav.example.com/leeef'
                  }
                />
              </div>
            ) : null}
            {value.syncBackend === 'webdav' ? (
              <div className="grid grid-cols-2 gap-3">
                <div className="grid gap-1.5">
                  <Label>用户名</Label>
                  <Input
                    value={value.syncUsername ?? ''}
                    onChange={(event) => patch({ syncUsername: event.target.value })}
                  />
                </div>
                <div className="grid gap-1.5">
                  <Label>密码</Label>
                  <PasswordInput
                    value={value.syncPassword ?? ''}
                    onChange={(event: any) => patch({ syncPassword: event.target.value })}
                  />
                </div>
              </div>
            ) : null}
            {value.syncBackend === 's3' ? (
              <>
                <div className="grid grid-cols-2 gap-3">
                  <div className="grid gap-1.5">
                    <Label>存储桶 (Bucket)</Label>
                    <Input
                      value={value.syncBucket ?? ''}
                      onChange={(event) => patch({ syncBucket: event.target.value })}
                    />
                  </div>
                  <div className="grid gap-1.5">
                    <Label>区域 (Region)</Label>
                    <Input
                      value={value.syncRegion ?? 'us-east-1'}
                      onChange={(event) => patch({ syncRegion: event.target.value })}
                    />
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <div className="grid gap-1.5">
                    <Label>Access Key</Label>
                    <Input
                      value={value.syncAccessKey ?? ''}
                      onChange={(event) => patch({ syncAccessKey: event.target.value })}
                    />
                  </div>
                  <div className="grid gap-1.5">
                    <Label>Secret Key</Label>
                    <PasswordInput
                      value={value.syncSecretKey ?? ''}
                      onChange={(event: any) => patch({ syncSecretKey: event.target.value })}
                    />
                  </div>
                </div>
                <div className="grid gap-1.5">
                  <Label>对象前缀 (Prefix)</Label>
                  <Input
                    value={value.syncPrefix ?? 'leeef'}
                    onChange={(event) => patch({ syncPrefix: event.target.value })}
                  />
                </div>
              </>
            ) : null}
          </CardContent>
        </Card>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle className="text-base">书籍与阅读数据同步</CardTitle>
          <CardDescription>
            使用已配置的 S3 / WebDAV 同步书籍、封面、进度、书摘、书签、分类与阅读时长。
            首次开启会上传本地书库，已配对设备会自动下载。所有内容在上传前加密。
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <SettingChoices
            label="同步范围"
            value={value.syncLibrary ? 'library' : 'settings'}
            onChange={(choice) => patch({ syncLibrary: choice === 'library' })}
            options={[
              { value: 'settings', label: '仅配置' },
              { value: 'library', label: '配置、书籍与阅读数据' },
            ]}
          />
          <SettingSwitch
            label="本机自动同步"
            checked={value.autoSync !== false}
            onChange={(autoSync) => patch({ autoSync })}
          />
          <p className="text-xs text-muted-foreground">保存后生效。自动同步在应用运行时每 30 秒检查一次；离线修改保留在本地，联网后重试。</p>
        </CardContent>
      </Card>

      {/* 5. EdgeEver 书摘同步 */}
      {desktop ? (
        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2">
              <NotebookPen className="size-4 text-primary" />
              EdgeEver 笔记同步
            </CardTitle>
            <CardDescription>
              每本书同步到同一篇笔记。同步会覆盖书摘区，保留标题、标签和书摘区外的内容。
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <SettingSwitch
              label="自动同步书摘到 EdgeEver"
              checked={value.edgeEverEnabled === true}
              onChange={(edgeEverEnabled) => patch({ edgeEverEnabled })}
            />
            <div className="grid gap-1.5">
              <Label htmlFor="edgeever-endpoint">实例地址</Label>
              <Input
                id="edgeever-endpoint"
                type="url"
                value={value.edgeEverEndpoint ?? ''}
                onChange={(event) => patch({ edgeEverEndpoint: event.target.value, edgeEverNotebookLabel: undefined })}
                placeholder="https://notes.example.com"
              />
            </div>
            <div className="grid gap-1.5">
              <Label htmlFor="edgeever-token">API Token</Label>
              <PasswordInput
                id="edgeever-token"
                value={value.edgeEverToken ?? ''}
                onChange={(event) => patch({ edgeEverToken: event.target.value })}
              />
              <p className="text-xs text-muted-foreground">需要 read:notebooks、read:memos 和 write:memos 权限。</p>
            </div>
            <div className="grid gap-1.5">
              <Label htmlFor="edgeever-notebook">目标笔记本</Label>
              <Select
                value={value.edgeEverNotebookId || 'none'}
                onValueChange={(id) => patch({
                  edgeEverNotebookId: id === 'none' ? '' : id,
                  edgeEverNotebookLabel: edgeEverNotebooks.find((notebook) => notebook.id === id),
                })}
              >
                <SelectTrigger id="edgeever-notebook" className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">尚未选择</SelectItem>
                  {edgeEverNotebooks.map((nb) => (
                    <SelectItem key={nb.id} value={nb.id}>
                      {nb.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="flex flex-wrap gap-2 pt-1">
              <Button
                variant="outline"
                size="sm"
                disabled={edgeEverBusy}
                onClick={() => {
                  setEdgeEverBusy(true)
                  void api
                    .saveSettings(value)
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
                size="sm"
                disabled={edgeEverBusy || !value.edgeEverEnabled || !value.edgeEverNotebookId}
                onClick={() => {
                  setEdgeEverBusy(true)
                  void api
                    .saveSettings(value)
                    .then(prepareEdgeEverExcerptChapters)
                    .then(() => api.edgeEverSyncAll())
                    .then((result) => {
                      if (result.errors.length) toast.error(result.errors.join('\n'))
                      else toast.success(`已同步 ${result.synced} 本，跳过 ${result.skipped} 本`)
                    })
                    .catch((cause) => toast.error(String(cause)))
                    .finally(() => setEdgeEverBusy(false))
                }}
              >
                立即同步全部书摘
              </Button>
            </div>
          </CardContent>
        </Card>
      ) : <EdgeEverStatusCard />}

      {/* 6. 设备配对与配置同步 */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <Share2 className="size-4 text-primary" />
            设备配对与状态
          </CardTitle>
          <CardDescription>生成配对码或加入其它设备，共享配置与已开启同步的书库</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <SyncCenter status={syncStatus} onStatus={setSyncStatus} />

          <p id="pairing-network-hint" className="flex items-start gap-2 text-sm text-muted-foreground">
            <Wifi aria-hidden="true" className="mt-0.5 size-4 shrink-0" />
            <span>配对时，两台设备需连接到同一局域网（例如同一 Wi-Fi）。</span>
          </p>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div className="grid gap-2 rounded-lg border p-3">
              <Label className="text-xs">让另一台设备加入</Label>
              <div className="flex items-center gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  aria-describedby="pairing-network-hint"
                  disabled={pairBusy}
                  onClick={() => {
                    setPairBusy(true)
                    void api
                      .pairingStart()
                      .then(async (offer) => {
                      setPair(offer)
                      setSyncStatus(await api.settingsSyncStatus())
                    })
                      .catch((cause) => toast.error(String(cause)))
                      .finally(() => setPairBusy(false))
                  }}
                >
                  生成配对码
                </Button>
                {pair ? (
                  <strong className="font-mono tracking-widest text-primary text-sm">
                    {pair.code}
                  </strong>
                ) : null}
              </div>
            </div>

            <div className="grid gap-2 rounded-lg border p-3">
              <Label className="text-xs">加入已有设备</Label>
              <div className="flex items-center gap-2">
                <Input
                  value={pairCode}
                  aria-describedby={
                    pairJoinError ? 'pairing-network-hint pairing-join-error' : 'pairing-network-hint'
                  }
                  disabled={pairBusy}
                  maxLength={12}
                  placeholder="12 位配对码"
                  className="font-mono uppercase tracking-widest text-xs h-8"
                  onChange={(event) => {
                    setPairCode(event.target.value.toUpperCase())
                    setPairJoinError('')
                  }}
                />
                <Button
                  size="sm"
                  disabled={pairBusy || pairCode.trim().length !== 12}
                  onClick={() => {
                    if (syncStatus?.paired) setJoinConfirmOpen(true)
                    else handleJoinExecute()
                  }}
                >
                  加入
                </Button>
              </div>
              {pairJoinError && (
                <p id="pairing-join-error" role="alert" className="text-sm text-destructive">
                  {pairJoinError}
                </p>
              )}
            </div>
          </div>
        </CardContent>
      </Card>

      <LibraryBackup />

      {/* 7. 灾难恢复 */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <KeyRound className="size-4 text-primary" />
            同步配置恢复包
          </CardTitle>
          <CardDescription>
            恢复包包含同步空间密钥与当前配置，不含书籍、进度或笔记，请另行保留这些数据。恢复包使用独立密码加密保存
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="grid gap-1.5">
            <Label>加密密码（至少 12 位）</Label>
            <PasswordInput
              value={recoveryPassword}
              onChange={(e: any) => setRecoveryPassword(e.target.value)}
              placeholder="请输入高强度密码"
            />
          </div>

          <div className="flex flex-wrap gap-2 pt-1">
            <Button
              variant="outline"
              size="sm"
              disabled={recoveryBusy || !syncStatus?.paired || recoveryPassword.length < 12}
              onClick={() => {
                setRecoveryBusy(true)
                void api
                  .settingsRecoveryExport(recoveryPassword)
                  .then(async (content) => {
                    setRecoveryPackage(content)
                    const saved = await api.saveTextFile(
                      `leeef-recovery-${new Date().toISOString().slice(0, 10)}.leeef-recovery`,
                      content,
                    )
                    if (saved.saved) toast.success('恢复包已导出')
                  })
                  .catch((cause) => toast.error(String(cause)))
                  .finally(() => setRecoveryBusy(false))
              }}
            >
              导出加密恢复包
            </Button>
            <Button
              variant="outline"
              size="sm"
              disabled={!recoveryPackage}
              onClick={() => {
                void navigator.clipboard
                  .writeText(recoveryPackage)
                  .then(() => toast.success('恢复包已复制到剪贴板'))
                  .catch((cause) => toast.error(String(cause)))
              }}
            >
              复制恢复包
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => recoveryFile.current?.click()}
            >
              选择本地文件
            </Button>
            <input
              ref={recoveryFile}
              type="file"
              className="hidden"
              accept=".leeef-recovery,application/json,text/plain"
              onChange={(event) => {
                const file = event.target.files?.[0]
                if (file) {
                  void file
                    .text()
                    .then(setRecoveryPackage)
                    .catch((cause) => toast.error(String(cause)))
                }
                event.target.value = ''
              }}
            />
          </div>

          <div className="grid gap-1.5">
            <Label className="text-xs">恢复包密文内容</Label>
            <Textarea
              value={recoveryPackage}
              onChange={(event) => setRecoveryPackage(event.target.value)}
              placeholder="粘贴从密码管理器导出的恢复包内容"
              className="min-h-20 font-mono text-xs"
            />
          </div>

          <Button
            size="sm"
            disabled={recoveryBusy || !recoveryPackage.trim() || recoveryPassword.length < 12}
            onClick={() => {
              if (syncStatus?.paired) setRecoveryConfirmOpen(true)
              else handleRecoveryExecute()
            }}
          >
            从恢复包恢复
          </Button>
        </CardContent>
      </Card>

      {/* 8. 本机 MCP 服务 */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <Database className="size-4 text-primary" />
            本机 MCP 服务 (Model Context Protocol)
          </CardTitle>
          <CardDescription>
            提供官方 rmcp Streamable HTTP 端点，供外部 AI 工具或脚本调用本地数据库
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="text-xs text-muted-foreground space-y-1 bg-muted/40 p-3 rounded-lg">
            <p>本地数据库：{dbPath || '…'}</p>
            <p className="font-semibold text-foreground">
              状态：{mcp.running ? `已在运行 (${mcp.endpoint})` : '未启动'}
            </p>
            {mcp.running && mcp.token ? (
              <p className="break-all font-mono text-[11px] select-all">
                Token: Bearer {mcp.token}
              </p>
            ) : null}
          </div>

          <div className="flex gap-2">
            <Button
              size="sm"
              onClick={() =>
                void api.mcpStart().then(setMcp).catch((cause) => toast.error(String(cause)))
              }
            >
              启动服务
            </Button>
            <Button size="sm" variant="outline" onClick={() => void api.mcpStop().then(setMcp)}>
              停止服务
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Bottom Save Bar */}
      <div className="flex justify-end pt-2">
        <Button onClick={handleSave} className="px-6">
          <Save className="size-4 mr-1.5" />
          保存全部设置
        </Button>
      </div>

      {/* Join Confirm Dialog */}
      <Dialog open={joinConfirmOpen} onOpenChange={setJoinConfirmOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>确认加入新同步空间？</DialogTitle>
            <DialogDescription>
              加入新的同步空间将替换当前设备的同步关系，确认继续吗？
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setJoinConfirmOpen(false)}>
              取消
            </Button>
            <Button onClick={handleJoinExecute}>确认替换并加入</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Recovery Confirm Dialog */}
      <Dialog open={recoveryConfirmOpen} onOpenChange={setRecoveryConfirmOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>确认导入恢复包？</DialogTitle>
            <DialogDescription>
              从恢复包导入会替换当前设备的同步空间和配置，确认继续吗？
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setRecoveryConfirmOpen(false)}>
              取消
            </Button>
            <Button onClick={handleRecoveryExecute}>确认恢复</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </main>
  )
}
