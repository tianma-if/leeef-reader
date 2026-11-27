import { useEffect, useState } from 'react'
import { Copy, Database } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { api, type McpStatus } from '../api'

export function McpSettings() {
  const [status, setStatus] = useState<McpStatus | null>(null)
  const [busy, setBusy] = useState(false)
  const [loadFailed, setLoadFailed] = useState(false)

  useEffect(() => {
    void api.mcpStatus().then(setStatus).catch(() => setLoadFailed(true))
  }, [])

  const config = status?.running && status.endpoint && status.token
    ? JSON.stringify({
      mcpServers: {
        'leeef-reader': {
          type: 'http',
          url: status.endpoint,
          headers: { Authorization: `Bearer ${status.token}` },
        },
      },
    }, null, 2)
    : null

  const changeService = async (enable: boolean) => {
    setBusy(true)
    try {
      setStatus(await (enable ? api.mcpStart() : api.mcpStop()))
    } catch (cause) {
      toast.error(`${enable ? '无法启动' : '无法停用'} MCP 服务：${String(cause)}`)
    } finally {
      setBusy(false)
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-base">
          <Database className="size-4 text-primary" />
          本机 MCP 服务
        </CardTitle>
        <CardDescription>
          授权本机 AI 工具读取和修改书库。启用后，服务随 Leeef Reader 启动。
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <div aria-live="polite" className="space-y-1 rounded-lg bg-muted/40 p-3 text-sm">
          <p className="font-medium">
            {loadFailed ? '无法读取服务状态' : status?.running ? '运行中' : status?.error ? '启动失败' : status ? '已停用' : '正在读取服务状态'}
          </p>
          {status?.error && <p className="break-words text-destructive">{status.error}</p>}
          {status?.endpoint && (
            <p className="break-all text-muted-foreground">
              Streamable HTTP <code className="select-all">{status.endpoint}</code>
            </p>
          )}
          {status?.databasePath && (
            <p className="break-all text-xs text-muted-foreground">本地数据库：{status.databasePath}</p>
          )}
        </div>

        <div className="flex flex-wrap gap-2">
          {config && (
            <Button size="sm" disabled={busy} onClick={async () => {
              try {
                await navigator.clipboard.writeText(config)
                toast.success('已复制 MCP 连接配置')
              } catch {
                toast.error('复制失败，请展开连接配置后手动复制')
              }
            }}>
              <Copy className="size-4" />
              复制完整 MCP 连接配置
            </Button>
          )}
          {status && !status.running && (
            <Button size="sm" disabled={busy} onClick={() => void changeService(true)}>
              {status.error ? '重试启动' : '启用 MCP 并获取配置'}
            </Button>
          )}
          {(status?.running || status?.error) && (
            <Button size="sm" variant="outline" disabled={busy} onClick={() => void changeService(false)}>
              停用 MCP
            </Button>
          )}
        </div>

        {config && (
          <details className="rounded-lg border p-3 text-sm">
            <summary className="cursor-pointer font-medium">MCP Server 连接配置</summary>
            <p className="mt-2 text-muted-foreground">
              此 JSON 适用于 Claude Code，包含访问令牌，请妥善保管。
            </p>
            <pre className="mt-3 whitespace-pre-wrap break-all rounded-md bg-muted p-3 text-xs">{config}</pre>
          </details>
        )}
      </CardContent>
    </Card>
  )
}
