import { invoke } from '@tauri-apps/api/core'

export type CaptureRect = {
  x: number
  y: number
  width: number
  height: number
}

export const isMobileShell = () =>
  /Android|iPhone|iPad|iPod/i.test(navigator.userAgent)

export const captureWebviewRegion = async (rect: CaptureRect, cover = false) => {
  const raw = await invoke<ArrayBuffer | number[]>('plugin:native-bridge|capture_webview_region', {
    payload: { ...rect, cover },
  })
  return raw instanceof ArrayBuffer ? new Uint8Array(raw) : new Uint8Array(raw)
}

export const setCoverProgress = (progress: number, forward: boolean, duration = 0) =>
  invoke('plugin:native-bridge|set_cover_progress', {
    payload: { progress, forward, duration: Math.max(0, Math.round(duration)) },
  })

export const uncoverWebview = () => invoke('plugin:native-bridge|uncover_webview')

export const probeWebviewReady = async () => {
  const result = await invoke<{ ready?: boolean }>('plugin:native-bridge|probe_webview_ready')
  return result?.ready === true
}
