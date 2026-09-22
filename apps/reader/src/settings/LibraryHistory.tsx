import { useRef, useState } from 'react'
import { toast } from 'sonner'
import { api, type LibraryHistoryEntry, type LibraryHistoryRecord } from '../api'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'

function VersionContent({ record }: { record: LibraryHistoryRecord | null }) {
  if (!record) return <p className="text-muted-foreground">当前记录不存在</p>
  const deleted = record.deleted || record.data.is_deleted === 1
  return <div className="space-y-2 text-sm break-words">
    <p className="text-xs text-muted-foreground">{new Date(record.modifiedAt).toLocaleString()} · 设备 {record.deviceId.slice(0, 8)}{deleted ? ' · 已删除' : ''}</p>
    {record.table === 'excerpts' ? <>
      <p className="whitespace-pre-wrap">{record.data.quote || '（无原文）'}</p>
      <p className="whitespace-pre-wrap text-muted-foreground">笔记：{record.data.note || '（无笔记）'}</p>
    </> : <>
      <p>{record.data.chapter_title || '阅读位置'} · {((record.data.progress ?? 0) * 100).toFixed(1)}%</p>
    </>}
  </div>
}

export function LibraryHistory({ onRestored }: { onRestored: () => void }) {
  const [open, setOpen] = useState(false)
  const [entries, setEntries] = useState<LibraryHistoryEntry[]>([])
  const [selected, setSelected] = useState<LibraryHistoryEntry | null>(null)
  const [loading, setLoading] = useState(false)
  const [restoring, setRestoring] = useState(false)
  const [error, setError] = useState('')
  const [hasMore, setHasMore] = useState(false)
  const [kind, setKind] = useState<'excerpts' | 'reading_progresses' | null>(null)
  const request = useRef(0)
  const load = async (beforeId: number | null = null, filter = kind) => {
    const sequence = ++request.current
    setLoading(true)
    setError('')
    if (beforeId === null) { setEntries([]); setSelected(null); setHasMore(false) }
    try {
      const next = await api.libraryHistory(beforeId, filter)
      if (sequence !== request.current) return
      setEntries((current) => beforeId === null ? next : [...current, ...next])
      setHasMore(next.length === 30)
    } catch (cause) { if (sequence === request.current) setError(String(cause)) }
    finally { if (sequence === request.current) setLoading(false) }
  }
  const restore = async () => {
    if (!selected) return
    setRestoring(true)
    setError('')
    try {
      const expected = selected.current ? { modifiedAt: selected.current.modifiedAt, deviceId: selected.current.deviceId } : null
      await api.libraryHistoryRestore(selected.id, expected)
      toast.success('已恢复为新版本，原版本仍可在历史中查看')
      onRestored()
      await load()
    } catch (cause) { setError(String(cause)) }
    finally { setRestoring(false) }
  }
  return <>
    <Button variant="outline" size="sm" onClick={() => { setOpen(true); void load() }}>历史版本与误删恢复</Button>
    <Dialog open={open} onOpenChange={(next) => {
      if (restoring) return
      setOpen(next)
      if (!next) { request.current++; setLoading(false); setSelected(null) }
    }}>
      <DialogContent className="max-h-[85dvh] overflow-y-auto sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>历史版本与误删恢复</DialogTitle>
          <DialogDescription>查看本机保留的书摘和阅读位置历史，包括同步冲突与本机修改。恢复结果会作为新版本参与已开启的书库同步。</DialogDescription>
        </DialogHeader>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <p className="text-xs text-muted-foreground">按历史收录顺序排列。更早未保留的版本无法找回。</p>
          <Button variant="outline" size="sm" disabled={loading || restoring} onClick={() => void load()}>刷新历史</Button>
        </div>
        {!selected ? <label className="flex items-center gap-2 text-sm">历史类型
          <select className="min-w-0 rounded-md border bg-background p-2" value={kind ?? ''} disabled={loading || restoring}
            onChange={(event) => { const filter = (event.target.value || null) as typeof kind; setKind(filter); void load(null, filter) }}>
            <option value="">全部</option><option value="excerpts">书摘与笔记</option><option value="reading_progresses">阅读位置</option>
          </select>
        </label> : null}
        {error ? <p role="alert" className="text-sm text-destructive break-words">{error}</p> : null}
        {selected ? <>
          <h3 className="font-semibold break-words">{selected.bookTitle} · {selected.record.table === 'excerpts' ? '书摘' : '阅读位置'}</h3>
          <div className="grid gap-3 sm:grid-cols-2">
            <section className="space-y-2 rounded-lg border p-3"><h4 className="text-sm font-medium">准备恢复的版本</h4><VersionContent record={selected.record} /></section>
            <section className="space-y-2 rounded-lg border p-3"><h4 className="text-sm font-medium">当前版本</h4><VersionContent record={selected.current} /></section>
          </div>
          <p className="text-sm">确认后将以所选内容替换当前记录，已删除的书摘会重新显示。当前版本仍会保留；若期间发生新修改，请刷新后重新选择。</p>
          {!selected.restorable ? <p className="text-sm text-destructive">请先恢复或重新导入这本书。</p> : null}
          <DialogFooter>
            <Button variant="outline" disabled={restoring} onClick={() => setSelected(null)}>返回列表</Button>
            <Button disabled={restoring || !selected.restorable} onClick={() => void restore()}>{restoring ? '正在恢复…' : '确认恢复此版本'}</Button>
          </DialogFooter>
        </> : <>
          {!loading && !error && entries.length === 0 ? <p className="py-6 text-center text-sm text-muted-foreground">暂无可恢复的历史版本</p> : null}
          <ul className="space-y-2">
            {entries.map((entry) => <li key={entry.id} className="rounded-lg border p-3">
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0 space-y-1">
                  <p className="text-sm font-medium break-words">{entry.bookTitle} · {entry.record.table === 'excerpts' ? '书摘' : '阅读位置'}</p>
                  <p className="text-xs text-muted-foreground">{new Date(entry.record.modifiedAt).toLocaleString()}{entry.current?.deleted || entry.current?.data.is_deleted === 1 ? ' · 当前已删除' : ''}</p>
                  <p className="line-clamp-2 text-xs break-words">{entry.record.table === 'excerpts' ? entry.record.data.note || entry.record.data.quote : `${entry.record.data.chapter_title || '阅读位置'} · ${((entry.record.data.progress ?? 0) * 100).toFixed(1)}%`}</p>
                </div>
                <Button variant="outline" size="sm" onClick={() => setSelected(entry)}>查看版本</Button>
              </div>
            </li>)}
          </ul>
          {loading ? <p role="status" className="text-sm">正在加载历史…</p> : hasMore ? <Button variant="outline" onClick={() => void load(entries[entries.length - 1]?.id ?? null)}>加载更多</Button> : null}
        </>}
      </DialogContent>
    </Dialog>
  </>
}
