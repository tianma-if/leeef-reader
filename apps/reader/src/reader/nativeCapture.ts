import { invoke } from '@tauri-apps/api/core'

export type CaptureRect = {
  x: number
  y: number
  width: number
  height: number
}

export const isMobileShell = () =>
  /Android|iPhone|iPad|iPod/i.test(navigator.userAgent)

export const captureWebviewRegion = async (rect: CaptureRect) => {
  const raw = await invoke<ArrayBuffer | number[]>('plugin:native-bridge|capture_webview_region', {
    payload: rect,
  })
  return raw instanceof ArrayBuffer ? new Uint8Array(raw) : new Uint8Array(raw)
}
