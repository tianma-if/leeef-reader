// Count only time for which a successfully opened reader is visible.
export function createReadingTimer(
  save: (seconds: number) => Promise<unknown>,
  now: () => number = () => performance.now(),
) {
  let activeSince: number | null = null
  let pendingMs = 0
  let queue = Promise.resolve()

  const checkpoint = () => {
    if (activeSince === null) return
    const current = now()
    pendingMs += Math.max(0, current - activeSince)
    activeSince = current
  }

  return {
    setActive(active: boolean) {
      checkpoint()
      activeSince = active ? now() : null
    },
    flush(): Promise<void> {
      checkpoint()
      const result = queue.then(async () => {
        const seconds = Math.floor(pendingMs / 1000)
        if (seconds < 1) return
        pendingMs -= seconds * 1000
        try {
          await save(seconds)
        } catch (cause) {
          pendingMs += seconds * 1000
          throw cause
        }
      })
      queue = result.catch(() => undefined)
      return result
    },
  }
}
