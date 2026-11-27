import { useEffect, useState } from 'react'
import { Copy, Info } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Card, CardAction, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { api } from '../api'

const platforms: Record<string, { name: string; webview: string }> = {
  android: { name: 'Android', webview: 'Android System WebView' },
  ios: { name: 'iOS', webview: 'WebKit' },
  linux: { name: 'Linux', webview: 'WebKitGTK' },
  macos: { name: 'macOS', webview: 'WebKit' },
  windows: { name: 'Windows', webview: 'WebView2' },
}

async function writeDiagnostics(text: string) {
  try {
    if (navigator.clipboard) {
      await navigator.clipboard.writeText(text)
      return true
    }
  } catch {
    // Some embedded WebViews block the Clipboard API on custom origins.
  }

  const focused = document.activeElement
  const input = document.createElement('textarea')
  input.value = text
  input.readOnly = true
  input.style.cssText = 'position:fixed;top:0;opacity:0;pointer-events:none'
  document.body.append(input)
  try {
    input.focus({ preventScroll: true })
    input.select()
    input.setSelectionRange(0, text.length)
    return document.execCommand('copy')
  } catch {
    return false
  } finally {
    input.remove()
    if (focused instanceof HTMLElement) focused.focus({ preventScroll: true })
  }
}

export function AboutCard() {
  const [info, setInfo] = useState<Awaited<ReturnType<typeof api.getAppInfo>> | null>(null)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    let disposed = false
    void api.getAppInfo().then((result) => {
      if (!disposed) setInfo(result)
    }).catch(() => {
      if (!disposed) setFailed(true)
    })
    return () => { disposed = true }
  }, [])

  const platform = info && platforms[info.platform]
  const fields = info ? [
    { label: '应用版本', value: info.version },
    { label: '操作系统', value: [platform?.name ?? info.platform, info.osVersion].filter(Boolean).join(' ') },
    { label: '应用架构', value: info.arch },
    { label: '构建类型', value: info.debug ? '调试构建' : '发布构建' },
    { label: 'Tauri 版本', value: info.tauriVersion },
    { label: 'WebView', value: [platform?.webview, info.webviewVersion].filter(Boolean).join(' ') || '未知' },
  ] : []

  const copyInfo = async () => {
    const details = fields.map(({ label, value }) => `${label}：${value}`)
    if (await writeDiagnostics(['Leeef Reader', ...details].join('\n'))) {
      toast.success('已复制应用信息')
    } else {
      toast.error('无法复制应用信息')
    }
  }

  return (
    <Card role="region" aria-labelledby="about-title">
      <CardHeader>
        <CardTitle className="self-center">
          <h2 id="about-title" className="flex items-center gap-2">
            <Info className="size-4 shrink-0 text-primary" aria-hidden="true" />
            关于 Leeef Reader
          </h2>
        </CardTitle>
        {info && (
          <CardAction>
            <Button variant="outline" size="sm" onClick={() => void copyInfo()}>
              <Copy aria-hidden="true" />
              复制信息
            </Button>
          </CardAction>
        )}
      </CardHeader>
      <CardContent>
        {info ? (
          <dl className="grid select-text grid-cols-2 gap-x-4 gap-y-3 text-sm sm:grid-cols-3">
            {fields.map(({ label, value }) => (
              <div key={label} className="min-w-0">
                <dt className="text-xs text-muted-foreground">{label}</dt>
                <dd className="mt-0.5 wrap-break-word font-medium">{value}</dd>
              </div>
            ))}
          </dl>
        ) : (
          <p role="status" className="text-sm text-muted-foreground">
            {failed ? '无法读取应用信息' : '正在读取应用信息…'}
          </p>
        )}
      </CardContent>
    </Card>
  )
}
