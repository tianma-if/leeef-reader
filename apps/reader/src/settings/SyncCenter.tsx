import { useState } from 'react'
import { RefreshCw } from 'lucide-react'
import { toast } from 'sonner'
import { api, type SettingsSyncStatus } from '../api'
import { Button } from '@/components/ui/button'
import { LibraryHistory } from './LibraryHistory'

const phases: Record<string, string> = {
  configuration: '同步配置', preparing: '检查本机书库', uploading: '上传文件',
  publishing: '发布书库更新', discovering: '读取其它设备的书库',
  downloading: '下载文件', merging: '合并阅读数据', complete: '同步完成',
}

export function SyncCenter({ status, onStatus }: {
  status: SettingsSyncStatus | null
  onStatus: (status: SettingsSyncStatus) => void
}) {
  const [requesting, setRequesting] = useState(false)
  const busy = requesting || Boolean(status?.running)
  const progress = status?.progress
  const transfer = progress && ['uploading', 'downloading'].includes(progress.phase)
  const retry = async () => {
    setRequesting(true)
    try {
      if (!status) { onStatus(await api.settingsSyncStatus()); return }
      const next = await api.settingsSyncNow()
      onStatus(next)
      if (!next.running) toast.success('同步完成')
    } catch (cause) {
      toast.error(String(cause))
      try { onStatus(await api.settingsSyncStatus()) } catch { /* Keep the visible last outcome. */ }
    } finally { setRequesting(false) }
  }

  return (
    <section aria-label="同步状态中心" className="space-y-3 rounded-lg border p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h3 className="text-sm font-semibold">同步状态中心</h3>
        <Button variant="outline" size="sm" disabled={busy || Boolean(status && (!status.paired || !status.configured))}
          onClick={() => void retry()}>
          <RefreshCw className={`size-3 ${busy ? 'animate-spin' : ''}`} />
          {busy ? '同步中…' : !status ? '读取状态' : status.lastError ? '重试同步' : '立即同步'}
        </Button>
      </div>
      <div className="space-y-1 text-xs" role="status" aria-live="polite">
        {!status ? <p>尚未取得同步状态，可点击“读取状态”重试。</p> : !status.paired ? <p>尚未加入同步空间，数据保存在本机。配对后可开启同步。</p>
          : !status.configured ? <p>尚未配置同步后端，请先在桌面端保存 S3 或 WebDAV 设置。</p>
          : <>
            <p>{busy ? phases[progress?.phase ?? ''] ?? '准备同步' : status.lastError ? '同步未完成' : status.lastSuccessAt ? '最近一次同步已完成' : '等待首次同步'}</p>
            <p className="text-muted-foreground">{status.libraryEnabled ? '配置、书籍与阅读数据' : '仅同步配置'} · {status.autoSync ? '应用运行时自动同步' : '手动同步'}</p>
            {status.libraryEnabled && status.pendingRecords != null ? <p>待发布的书库记录：{status.pendingRecords} 条</p> : null}
            {(busy || status.lastError) && progress?.currentItem ? <p className="break-words">当前文件：{progress.currentItem}</p> : null}
            {(busy || status.lastError) && transfer ? <>
              <p>{phases[progress.phase]}：已完成 {progress.completed} / {progress.total} 个，剩余 {Math.max(0, progress.total - progress.completed)} 个（含封面）</p>
              {progress.total > 0 ? <progress className="h-2 w-full accent-primary" aria-label={phases[progress.phase]} value={progress.completed} max={progress.total} /> : null}
            </> : null}
            {status.lastError ? <div className="rounded-md bg-destructive/10 p-2 text-destructive break-words">
              <p>{phases[progress?.phase ?? ''] ?? '同步'}失败：{status.lastError}</p>
              <p className="mt-1">请检查网络和同步服务配置后重试，已成功传输的文件会复用。</p>
            </div> : null}
            {status.lastAttemptAt ? <p className="text-muted-foreground">最近尝试：{new Date(status.lastAttemptAt).toLocaleString()}</p> : null}
            {status.lastSuccessAt ? <p className="text-muted-foreground">最近成功：{new Date(status.lastSuccessAt).toLocaleString()}</p> : null}
          </>}
      </div>
      <LibraryHistory onRestored={() => { void api.settingsSyncStatus().then(onStatus).catch(() => undefined) }} />
    </section>
  )
}
