import { useState } from 'react'
import { toast } from 'sonner'
import { api, type BackupPreview } from '../api'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'

export function LibraryBackup() {
  const [password, setPassword] = useState('')
  const [packageText, setPackageText] = useState('')
  const [fileName, setFileName] = useState('')
  const [preview, setPreview] = useState<BackupPreview | null>(null)
  const [preferBackup, setPreferBackup] = useState(false)
  const [busy, setBusy] = useState(false)

  const run = async (action: () => Promise<void>) => {
    setBusy(true)
    try { await action() } catch (cause) { toast.error(String(cause)) }
    finally { setBusy(false) }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">书库备份与恢复</CardTitle>
        <CardDescription>
          将书籍、封面、分类、进度、书摘、书签和阅读时长保存为加密文件，无需云服务或设备配对。
          服务凭据请另行导出下方的同步配置恢复包。当前支持总计 128 MiB 的书籍与封面。
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <Label htmlFor="library-backup-password">独立备份密码（至少 12 位）</Label>
        <Input id="library-backup-password" type="password" autoComplete="new-password"
          disabled={busy} value={password} onChange={(event) => { setPassword(event.target.value); setPreview(null) }} />
        <p className="text-xs text-muted-foreground">恢复时需要同一密码，请将密码与备份文件分开保管。</p>
        <Button disabled={busy || [...password].length < 12} onClick={() => void run(async () => {
          const content = await api.libraryBackupExport(password)
          const { saved } = await api.saveTextFile(`Leeef-${new Date().toISOString().slice(0, 10)}.leeef-backup`, content)
          if (saved) toast.success('书库备份已保存')
        })}>{busy ? '正在处理…' : '导出加密书库备份'}</Button>
        <div className="space-y-2 border-t pt-3">
          <Label htmlFor="library-backup-file">选择要恢复的备份</Label>
          <Input id="library-backup-file" type="file" accept=".leeef-backup" disabled={busy}
            onChange={(event) => {
              const file = event.target.files?.[0]
              event.target.value = ''
              setPreview(null)
              setPackageText('')
              setFileName('')
              if (file) void run(async () => {
                if (file.size > 384 * 1024 * 1024) throw new Error('备份文件超过当前支持大小')
                const content = await file.text()
                setPackageText(content)
                setFileName(file.name)
              })
            }} />
          {fileName ? <p className="text-xs break-all">{fileName}</p> : null}
          <Button variant="outline" disabled={busy || !packageText || [...password].length < 12}
            onClick={() => void run(async () => setPreview(await api.libraryBackupPreview(packageText, password)))}>
            校验并预览备份
          </Button>
        </div>
        <Dialog open={preview !== null} onOpenChange={(open) => { if (!open && !busy) setPreview(null) }}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>恢复书库备份</DialogTitle>
              <DialogDescription>
                {preview ? `${preview.books} 本书、${preview.excerpts} 条书摘、${preview.bookmarks} 个书签，共 ${(preview.bytes / 1024 / 1024).toFixed(1)} MiB。其中 ${preview.matchingBooks} 本已在本机。` : ''}
              </DialogDescription>
            </DialogHeader>
            <Label htmlFor="backup-conflicts">已有记录的处理方式</Label>
            <Select value={preferBackup ? 'backup' : 'local'} disabled={busy}
              onValueChange={(value) => setPreferBackup(value === 'backup')}>
              <SelectTrigger id="backup-conflicts"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="local">合并，保留较新的记录</SelectItem>
                <SelectItem value="backup">匹配记录以备份版本为准</SelectItem>
              </SelectContent>
            </Select>
            <p className="text-xs text-muted-foreground">
              {preferBackup ? '备份中的匹配记录会覆盖本机版本，可用于找回误删书摘或旧进度。本机独有书籍保留。' : '合并书库，不覆盖本机较新的修改；同一书籍文件不会重复导入。'}
              开启书库同步后，恢复结果也会同步到其它设备。
            </p>
            <DialogFooter>
              <Button variant="outline" disabled={busy} onClick={() => setPreview(null)}>取消</Button>
              <Button disabled={busy} onClick={() => void run(async () => {
                await api.libraryBackupRestore(packageText, password, preferBackup)
                setPreview(null)
                setPackageText('')
                setFileName('')
                toast.success('书库恢复完成')
              })}>{busy ? '恢复中…' : '确认恢复'}</Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </CardContent>
    </Card>
  )
}
