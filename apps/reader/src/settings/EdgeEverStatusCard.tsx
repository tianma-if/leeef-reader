import { useEffect, useState } from 'react'
import { NotebookPen } from 'lucide-react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { api, type EdgeEverStatus } from '../api'

const attemptDate = new Intl.DateTimeFormat('zh-CN', { dateStyle: 'medium', timeStyle: 'short' })

export function EdgeEverStatusCard() {
  const [status, setStatus] = useState<EdgeEverStatus>()
  const [unavailable, setUnavailable] = useState(false)

  useEffect(() => {
    let stopped = false
    let revision = 0
    let requestedTarget: string | null = null

    const refresh = async () => {
      if (stopped) return
      const current = ++revision
      try {
        const next = await api.edgeEverStatus()
        if (stopped || current !== revision) return
        setStatus(next)
        setUnavailable(false)
        if (requestedTarget === next.targetKey) return
        requestedTarget = next.targetKey
        if (next.targetKey) {
          void api.edgeEverNotebooks().then(() => refresh()).catch(() => undefined)
        }
      } catch {
        if (!stopped && current === revision) setUnavailable(true)
      }
    }
    const refreshWhenVisible = () => {
      if (document.visibilityState === 'visible') void refresh()
    }
    const refreshAfterReconnect = () => {
      requestedTarget = null
      void refresh()
    }

    void refresh()
    const timer = window.setInterval(refreshWhenVisible, 5000)
    document.addEventListener('visibilitychange', refreshWhenVisible)
    window.addEventListener('online', refreshAfterReconnect)
    return () => {
      stopped = true
      window.clearInterval(timer)
      document.removeEventListener('visibilitychange', refreshWhenVisible)
      window.removeEventListener('online', refreshAfterReconnect)
    }
  }, [])

  const attempt = status?.lastAttempt
  const enabledLabel = status?.enabled
    ? status.configured ? '已开启' : '已开启，配置未完成'
    : '未开启'

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-base">
          <NotebookPen className="size-4 text-primary" />
          EdgeEver 笔记同步
        </CardTitle>
        <CardDescription>在桌面端配置，手机通过可信设备同步接收设置。</CardDescription>
      </CardHeader>
      <CardContent aria-live="polite">
        {status ? (
          <dl className="divide-y rounded-lg border px-3 text-sm">
            <div className="flex justify-between gap-3 py-2.5">
              <dt className="shrink-0 text-muted-foreground">书摘同步</dt>
              <dd className="text-right font-medium">{enabledLabel}</dd>
            </div>
            <div className="flex justify-between gap-3 py-2.5">
              <dt className="shrink-0 text-muted-foreground">目标笔记本</dt>
              <dd className="min-w-0 break-words text-right font-medium">
                {status.notebookName ?? (status.notebookSelected ? '名称暂不可用' : '尚未选择')}
              </dd>
            </div>
            <div className="flex justify-between gap-3 py-2.5">
              <dt className="shrink-0 text-muted-foreground">本机最近一次同步</dt>
              <dd className="text-right">
                <span className={attempt && !attempt.succeeded ? 'font-medium text-destructive' : 'font-medium'}>
                  {attempt ? attempt.succeeded ? '成功' : '失败' : '暂无同步记录'}
                </span>
                {attempt && (
                  <time className="block text-xs text-muted-foreground" dateTime={new Date(attempt.finishedAt).toISOString()}>
                    {attemptDate.format(attempt.finishedAt)}
                  </time>
                )}
              </dd>
            </div>
          </dl>
        ) : (
          <p className="text-sm text-muted-foreground">{unavailable ? '暂时无法读取同步状态' : '正在读取同步状态…'}</p>
        )}
      </CardContent>
    </Card>
  )
}
