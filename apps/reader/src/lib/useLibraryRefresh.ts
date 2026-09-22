import { useEffect, useRef } from 'react'
import { listen } from '@tauri-apps/api/event'

export function useLibraryRefresh(refresh: () => void | Promise<unknown>) {
  const latest = useRef(refresh)
  latest.current = refresh
  useEffect(() => {
    let disposed = false
    const subscription = listen('library-synced', () => {
      if (!disposed) void Promise.resolve(latest.current()).catch(() => undefined)
    }).catch(() => () => undefined)
    return () => {
      disposed = true
      void subscription.then((stop) => stop()).catch(() => undefined)
    }
  }, [])
}
