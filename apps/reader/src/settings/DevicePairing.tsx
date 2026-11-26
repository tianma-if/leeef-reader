import { useEffect, useRef, useState } from 'react'
import { FileUp, Monitor, ScanLine } from 'lucide-react'
import { toast } from 'sonner'
import { api, isMobile, type PairingHostStatus, type PairingOffer, type PairingPeer, type SettingsSyncStatus } from '../api'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'

type JoinAction =
  | { kind: 'peer'; peer: PairingPeer }
  | { kind: 'scan' }
  | { kind: 'code' }
  | { kind: 'import' }
type Operation = JoinAction['kind'] | 'host' | 'decision' | 'export'

function PairingQr({ qr }: { qr: NonNullable<PairingOffer['qr']> }) {
  const canvas = useRef<HTMLCanvasElement>(null)
  const margin = 4
  const scale = 4
  const size = (qr.width + 2 * margin) * scale

  useEffect(() => {
    const context = canvas.current?.getContext('2d')
    if (!context) return
    context.fillStyle = '#fff'
    context.fillRect(0, 0, size, size)
    context.fillStyle = '#000'
    for (let row = 0; row < qr.width; row++) {
      for (let col = 0; col < qr.width; col++) {
        if (qr.modules[row * qr.width + col] === '1') {
          context.fillRect((col + margin) * scale, (row + margin) * scale, scale, scale)
        }
      }
    }
  }, [qr, size])

  return (
    <canvas
      ref={canvas}
      width={size}
      height={size}
      className="mx-auto block h-auto w-56 max-w-full rounded-md [image-rendering:pixelated]"
      role="img"
      aria-label="配对二维码"
    />
  )
}

export function DevicePairing({
  open,
  onOpenChange,
  status,
  onStatus,
  onImported,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  status: SettingsSyncStatus | null
  onStatus: (status: SettingsSyncStatus) => void
  onImported: () => void
}) {
  const mobile = isMobile()
  const [peers, setPeers] = useState<PairingPeer[]>([])
  const [searchError, setSearchError] = useState('')
  const [searching, setSearching] = useState(true)
  const [refresh, setRefresh] = useState(0)
  const [offer, setOffer] = useState<PairingOffer | null>(null)
  const [pending, setPending] = useState<PairingHostStatus['pending']>(null)
  const [code, setCode] = useState('')
  const [verification, setVerification] = useState('')
  const [replacement, setReplacement] = useState<JoinAction | null>(null)
  const [busy, setBusy] = useState<Operation | null>(null)
  const [error, setError] = useState('')
  const [recoveryOpen, setRecoveryOpen] = useState(false)
  const [password, setPassword] = useState('')
  const [packageText, setPackageText] = useState('')
  const [filename, setFilename] = useState('')
  const fileInput = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (!open || offer || busy) return
    let stopped = false
    let timer: number | undefined
    const search = async () => {
      try {
        const found = await api.pairingNearby()
        if (stopped) return
        setPeers(found)
        setSearchError('')
      } catch (cause) {
        if (stopped) return
        setPeers([])
        setSearchError(String(cause))
      }
      setSearching(false)
      timer = window.setTimeout(() => void search(), 2500)
    }
    void search()
    return () => {
      stopped = true
      window.clearTimeout(timer)
    }
  }, [open, offer, busy, refresh])

  const sessionId = offer?.sessionId
  useEffect(() => {
    if (!open || !sessionId) return
    let stopped = false
    let timer: number | undefined
    const poll = async () => {
      try {
        const current = await api.pairingStatus(sessionId)
        if (stopped) return
        setPending(current.pending)
        if (!current.active) {
          setOffer(null)
          if (current.completed) {
            toast.success('设备配对成功')
            void api.settingsSyncStatus().then(onStatus).catch(() => undefined)
          } else {
            setError('配对邀请已结束，可以重新开始。')
          }
          return
        }
      } catch (cause) {
        if (!stopped) setError(String(cause))
      }
      if (!stopped) timer = window.setTimeout(() => void poll(), 600)
    }
    void poll()
    return () => {
      stopped = true
      window.clearTimeout(timer)
      void api.pairingStop(sessionId).catch(() => undefined)
    }
  }, [open, sessionId, onStatus])

  const finishJoin = (latest: SettingsSyncStatus, imported: boolean) => {
    onStatus(latest)
    onImported()
    toast.success(imported ? '配置已导入' : '设备配对成功')
  }

  const execute = async (action: JoinAction, replaceExisting: boolean) => {
    setReplacement(null)
    setError('')
    setVerification('')
    setBusy(action.kind)
    try {
      if (action.kind === 'import') {
        const latest = await api.settingsRecoveryImport(packageText, password, replaceExisting)
        setPassword('')
        setPackageText('')
        setFilename('')
        finishJoin(latest, true)
        void api.settingsSyncNow().then(onStatus).catch(() => undefined)
      } else {
        const latest = action.kind === 'peer'
          ? await api.pairingJoinPeer(action.peer, replaceExisting, setVerification)
          : action.kind === 'scan'
            ? await api.pairingScanQr(replaceExisting)
            : await api.pairingJoin(code, replaceExisting)
        if (latest) {
          setCode('')
          finishJoin(latest, false)
        }
      }
    } catch (cause) {
      setError(String(cause))
    } finally {
      setVerification('')
      setBusy(null)
    }
  }

  const requestJoin = (action: JoinAction) => {
    setError('')
    if (status?.paired) setReplacement(action)
    else void execute(action, false)
  }

  const beginHosting = async () => {
    setBusy('host')
    setError('')
    try {
      const invite = await api.pairingStart()
      setOffer(invite)
      void api.settingsSyncStatus().then(onStatus).catch(() => undefined)
    } catch (cause) {
      setError(String(cause))
    } finally {
      setBusy(null)
    }
  }

  const confirmNearby = async (approve: boolean) => {
    if (!offer || !pending) return
    setBusy('decision')
    setError('')
    try {
      await api.pairingDecide(offer.sessionId, pending.id, approve)
      setPending(null)
    } catch (cause) {
      setError(String(cause))
    } finally {
      setBusy(null)
    }
  }

  const exportPackage = async () => {
    setBusy('export')
    setError('')
    try {
      const content = await api.settingsRecoveryExport(password)
      setFilename('')
      setPackageText(content)
      void api.settingsSyncStatus().then(onStatus).catch(() => undefined)
      const name = `leeef-recovery-${new Date().toISOString().slice(0, 10)}.leeef-recovery`
      const result = await api.saveTextFile(name, content)
      if (result.saved) toast.success('配置文件已导出')
    } catch (cause) {
      setError(String(cause))
    } finally {
      setBusy(null)
    }
  }

  const close = (next: boolean) => {
    if (!next && busy) return
    if (!next) {
      setOffer(null)
      setPending(null)
      setPeers([])
      setSearchError('')
      setSearching(true)
      setCode('')
      setError('')
      setRecoveryOpen(false)
      setReplacement(null)
      setPassword('')
      setPackageText('')
      setFilename('')
    }
    onOpenChange(next)
  }

  return (
    <Dialog open={open} onOpenChange={close}>
      <DialogContent className="max-h-[86dvh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>设备配对</DialogTitle>
          <DialogDescription>
            {mobile ? '在电脑端打开设备配对，点击「开始配对」。' : '开始配对后，在手机的设备配对页选择这台电脑，或扫描二维码。'}
          </DialogDescription>
        </DialogHeader>

        {!mobile && !offer && (
          <Button onClick={() => void beginHosting()} disabled={!!busy}>
            <Monitor className="size-4" />
            {busy === 'host' ? '正在开启配对…' : '开始配对'}
          </Button>
        )}

        {offer ? (
          <section className="grid gap-3 rounded-lg border p-4">
            <div className="flex items-center justify-between gap-2">
              <h3 className="font-medium">等待另一台设备配对</h3>
              <Button
                size="sm"
                variant="outline"
                disabled={!!busy}
                onClick={() => { setPending(null); setOffer(null) }}
              >
                停止配对
              </Button>
            </div>
            {pending && (
              <div className="grid gap-2 rounded-lg bg-muted p-3">
                <p className="text-sm break-words">{pending.deviceName} 请求加入。请核对两台设备上的确认码。</p>
                <strong className="font-mono text-lg tracking-wider">{pending.verification}</strong>
                <div className="flex flex-wrap gap-2">
                  <Button size="sm" onClick={() => void confirmNearby(true)} disabled={!!busy}>
                    一致，允许加入
                  </Button>
                  <Button size="sm" variant="outline" onClick={() => void confirmNearby(false)} disabled={!!busy}>
                    拒绝
                  </Button>
                </div>
              </div>
            )}
            {offer.qr ? <PairingQr qr={offer.qr} /> : <p className="text-sm text-muted-foreground">连接 Wi-Fi 或网线后可生成直连二维码。</p>}
            <div className="flex flex-wrap items-center justify-center gap-2 text-sm">
              <span className="text-muted-foreground">配对码</span>
              <strong className="font-mono tracking-wider">{offer.code}</strong>
            </div>
          </section>
        ) : (
          <>
            <section className="grid gap-2">
              <div className="flex items-center justify-between gap-2">
                <h3 className="font-medium">附近等待配对的设备</h3>
                <Button
                  size="sm"
                  variant="ghost"
                  disabled={!!busy}
                  onClick={() => { setSearching(true); setRefresh((value) => value + 1) }}
                >
                  刷新
                </Button>
              </div>
              {peers.map((peer) => (
                <Button
                  key={peer.sessionId}
                  variant="outline"
                  className="h-auto justify-start py-2.5 whitespace-normal break-all"
                  disabled={!!busy}
                  onClick={() => requestJoin({ kind: 'peer', peer })}
                >
                  <Monitor className="size-4 shrink-0" />
                  {peer.name}
                </Button>
              ))}
              {!peers.length && (
                <p className="text-sm text-muted-foreground" role="status">
                  {searching ? '正在查找附近设备…' : searchError || '暂未找到正在等待配对的设备。'}
                </p>
              )}
              {busy === 'peer' && (
                <div className="grid gap-2 rounded-lg border p-3">
                  <p className="text-sm" role="status">
                    {verification ? '请在电脑上核对这组确认码并允许加入。' : '正在连接配对设备…'}
                  </p>
                  {verification && <strong className="font-mono text-lg tracking-wider">{verification}</strong>}
                  <Button size="sm" variant="outline" className="w-fit"
                    onClick={() => void api.pairingCancelJoin().catch((cause) => setError(String(cause)))}>
                    取消连接
                  </Button>
                </div>
              )}
            </section>

          </>
        )}

        <div className="flex flex-wrap gap-2">
          {mobile && !offer && (
            <Button variant="outline" disabled={!!busy} onClick={() => requestJoin({ kind: 'scan' })}>
              <ScanLine className="size-4" /> 扫码直连
            </Button>
          )}
          <Button variant="outline" disabled={!!busy} onClick={() => setRecoveryOpen((value) => !value)} aria-expanded={recoveryOpen}>
            <FileUp className="size-4" /> {mobile ? '导入配置文件' : '导入或导出配置文件'}
          </Button>
        </div>

        {replacement && (
          <section className="grid gap-2 rounded-lg border p-3">
            <p className="text-sm">本机已有同步空间。确认继续后，新配置可能替换当前同步关系。</p>
            <div className="flex flex-wrap gap-2">
              <Button size="sm" onClick={() => void execute(replacement, true)}>确认继续</Button>
              <Button size="sm" variant="outline" onClick={() => setReplacement(null)}>取消</Button>
            </div>
          </section>
        )}

        {error && <p role="alert" className="text-sm text-destructive">{error}</p>}

        {recoveryOpen && (
          <section className="grid gap-3 rounded-lg border p-3">
            <h3 className="font-medium">同步配置恢复包</h3>
            <p className="text-sm text-muted-foreground">
              选择另一台设备导出的 .leeef-recovery 文件，输入导出时设置的密码。此操作无需局域网连接。
            </p>
            <Input ref={fileInput} type="file" className="hidden" aria-label="配置恢复包文件"
              onChange={(event) => {
                const file = event.currentTarget.files?.[0]
                event.currentTarget.value = ''
                if (!file) return
                setError('')
                void file.text()
                  .then((text) => { setPackageText(text); setFilename(file.name) })
                  .catch((cause) => setError(String(cause)))
              }}
            />
            <div className="flex flex-wrap items-center gap-2">
              <Button variant="outline" size="sm" disabled={!!busy} onClick={() => fileInput.current?.click()}>
                选择本地文件
              </Button>
              {filename && <span className="break-all text-sm text-muted-foreground">{filename}</span>}
            </div>
            <div className="grid gap-1.5">
              <Label htmlFor="pairing-recovery-password">恢复密码（至少 12 位）</Label>
              <Input id="pairing-recovery-password" type="password" value={password}
                onChange={(event) => setPassword(event.target.value)} autoComplete="off" disabled={!!busy} />
            </div>
            <div className="flex flex-wrap gap-2">
              <Button size="sm" disabled={!!busy || !packageText.trim() || password.length < 12}
                onClick={() => requestJoin({ kind: 'import' })}>
                {busy === 'import' ? '正在导入…' : '导入配置'}
              </Button>
              <Button size="sm" variant="outline" disabled={!!busy || password.length < 12 || !(status?.paired || status?.configured)}
                onClick={() => void exportPackage()}>
                {busy === 'export' ? '正在导出…' : '导出加密恢复包'}
              </Button>
            </div>
            <details>
              <summary className="cursor-pointer text-sm text-muted-foreground">恢复包密文</summary>
              <Textarea className="mt-2 font-mono text-xs" aria-label="恢复包密文" value={packageText}
                onChange={(event) => { setPackageText(event.target.value); setFilename('') }}
                disabled={!!busy} />
              <Button variant="ghost" size="sm" disabled={!packageText.trim()}
                onClick={() => void navigator.clipboard.writeText(packageText)
                  .then(() => toast.success('恢复包已复制')).catch((cause) => setError(String(cause)))}>
                复制恢复包
              </Button>
            </details>
          </section>
        )}

        {!offer && (
          <details>
            <summary className="cursor-pointer text-sm text-muted-foreground">使用配对码</summary>
            <div className="mt-2 flex gap-2">
              <Input
                aria-label="12 位配对码"
                placeholder="12 位配对码"
                value={code}
                maxLength={12}
                disabled={!!busy}
                className="font-mono uppercase tracking-wider"
                onChange={(event) => { setCode(event.target.value.toUpperCase()); setError('') }}
              />
              <Button disabled={!!busy || code.trim().length !== 12} onClick={() => requestJoin({ kind: 'code' })}>
                加入
              </Button>
            </div>
          </details>
        )}

        {mobile && !offer && (
          <Button variant="ghost" className="justify-self-start" disabled={!!busy} onClick={() => void beginHosting()}>
            {busy === 'host' ? '正在开启配对…' : '让另一台设备加入'}
          </Button>
        )}
      </DialogContent>
    </Dialog>
  )
}
