import { useEffect, useRef, useState } from 'react'
import { invoke } from '@tauri-apps/api/core'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

type MobileUpdateStatus = {
  platform: 'android' | 'ios'
  state:
    | 'available'
    | 'awaitingConsent'
    | 'pending'
    | 'downloading'
    | 'downloaded'
    | 'installing'
    | 'failed'
    | 'canceled'
    | 'idle'
    | 'unavailable'
  currentVersion?: string
  availableVersion?: string
  bytesDownloaded?: number
  totalBytes?: number
}

type UpdatePrompt =
  | { kind: 'restart'; platform: 'desktop' | 'android'; version?: string }
  | { kind: 'appStore'; version?: string }

const DESKTOP_CHECK_INTERVAL_MS = 5 * 60 * 1000
const MOBILE_CHECK_INTERVAL_MS = 6 * 60 * 60 * 1000
const ANDROID_POLL_INTERVAL_MS = 2 * 1000

const mobilePlatform = () => {
  if (/Android/i.test(navigator.userAgent)) return 'android' as const
  if (
    /iPhone|iPad|iPod/i.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)
  ) {
    return 'ios' as const
  }
  return undefined
}

export function UpdateCoordinator() {
  const [prompt, setPrompt] = useState<UpdatePrompt | null>(null)
  const [applying, setApplying] = useState(false)
  const checkRunning = useRef(false)
  const androidFlowStarted = useRef(false)
  const androidConsentPolls = useRef(0)
  const preparedVersion = useRef<string | undefined>(undefined)
  const dismissedIosVersion = useRef<string | undefined>(undefined)

  useEffect(() => {
    let disposed = false
    let androidPollTimer: number | undefined
    const platform = mobilePlatform()

    const scheduleAndroidPoll = (check: () => Promise<void>) => {
      window.clearTimeout(androidPollTimer)
      androidPollTimer = window.setTimeout(() => void check(), ANDROID_POLL_INTERVAL_MS)
    }

    const checkAndroid = async () => {
      const status = await invoke<MobileUpdateStatus>(
        'plugin:native-bridge|check_mobile_update',
      )
      if (disposed) return
      if (status.state === 'downloaded') {
        preparedVersion.current = status.availableVersion
        setPrompt({ kind: 'restart', platform: 'android', version: status.availableVersion })
        return
      }
      if (status.state === 'available' && !androidFlowStarted.current) {
        androidFlowStarted.current = true
        androidConsentPolls.current = 0
        const started = await invoke<MobileUpdateStatus>(
          'plugin:native-bridge|start_mobile_update',
        )
        if (disposed) return
        if (started.state === 'downloaded') {
          preparedVersion.current = started.availableVersion
          setPrompt({ kind: 'restart', platform: 'android', version: started.availableVersion })
          return
        }
        scheduleAndroidPoll(checkAndroid)
        return
      }
      if (
        status.state === 'available' &&
        androidFlowStarted.current &&
        androidConsentPolls.current < 60
      ) {
        androidConsentPolls.current += 1
        scheduleAndroidPoll(checkAndroid)
        return
      }
      if (
        status.state === 'awaitingConsent' ||
        status.state === 'pending' ||
        status.state === 'downloading' ||
        status.state === 'installing'
      ) {
        if (status.state !== 'awaitingConsent') androidConsentPolls.current = 0
        scheduleAndroidPoll(checkAndroid)
      }
    }

    const checkIos = async () => {
      const status = await invoke<MobileUpdateStatus>(
        'plugin:native-bridge|check_mobile_update',
      )
      if (
        !disposed &&
        status.state === 'available' &&
        status.availableVersion !== dismissedIosVersion.current
      ) {
        setPrompt({ kind: 'appStore', version: status.availableVersion })
      }
    }

    const checkDesktop = async () => {
      const { check } = await import('@tauri-apps/plugin-updater')
      const update = await check({ timeout: 15_000 })
      if (!update || disposed || preparedVersion.current === update.version) return
      await update.downloadAndInstall()
      if (disposed) return
      preparedVersion.current = update.version
      setPrompt({ kind: 'restart', platform: 'desktop', version: update.version })
    }

    const checkForUpdate = async () => {
      if (checkRunning.current || document.visibilityState !== 'visible') return
      checkRunning.current = true
      try {
        if (platform === 'android') await checkAndroid()
        else if (platform === 'ios') await checkIos()
        else await checkDesktop()
      } catch (error) {
        console.info('Update check unavailable', error)
      } finally {
        checkRunning.current = false
      }
    }

    const onVisible = () => {
      if (document.visibilityState === 'visible') void checkForUpdate()
    }
    const interval = window.setInterval(
      () => void checkForUpdate(),
      platform ? MOBILE_CHECK_INTERVAL_MS : DESKTOP_CHECK_INTERVAL_MS,
    )
    document.addEventListener('visibilitychange', onVisible)
    window.addEventListener('online', checkForUpdate)
    void checkForUpdate()

    return () => {
      disposed = true
      checkRunning.current = false
      window.clearInterval(interval)
      window.clearTimeout(androidPollTimer)
      document.removeEventListener('visibilitychange', onVisible)
      window.removeEventListener('online', checkForUpdate)
    }
  }, [])

  const closePrompt = () => {
    if (prompt?.kind === 'appStore') dismissedIosVersion.current = prompt.version
    setPrompt(null)
  }

  const applyUpdate = async () => {
    if (!prompt || applying) return
    setApplying(true)
    try {
      if (prompt.kind === 'appStore') {
        await invoke('plugin:native-bridge|open_mobile_store')
        closePrompt()
        setApplying(false)
        return
      }
      if (prompt.platform === 'android') {
        await invoke('plugin:native-bridge|complete_mobile_update')
        return
      }
      const { relaunch } = await import('@tauri-apps/plugin-process')
      await relaunch()
    } catch (error) {
      setApplying(false)
      toast.error(`无法应用更新：${String(error)}`)
    }
  }

  const isAppStore = prompt?.kind === 'appStore'

  return (
    <Dialog open={Boolean(prompt)} onOpenChange={(open) => !open && closePrompt()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{isAppStore ? '发现新版本' : '更新已准备好'}</DialogTitle>
          <DialogDescription>
            {isAppStore
              ? `Leeef Reader ${prompt?.version ?? '新版本'} 已在 App Store 提供。iOS 会按系统的自动更新设置下载安装，也可以现在前往 App Store。`
              : `Leeef Reader ${prompt?.version ?? '新版本'} 已下载并完成安装准备，重启应用即可使用。`}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button type="button" variant="outline" disabled={applying} onClick={closePrompt}>
            稍后
          </Button>
          <Button type="button" disabled={applying} onClick={() => void applyUpdate()}>
            {applying ? '正在处理…' : isAppStore ? '前往 App Store' : '立即重启'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
