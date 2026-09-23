/** Keep one follow-up intent: rapid input must not interrupt a turn or build
 * a long backlog that keeps flipping after the reader stops. */
export class TurnQueue {
  private pending: (() => Promise<void>) | null = null
  busy = false

  constructor(private readonly onError: (error: unknown) => void) {}

  run(action: () => Promise<void>) {
    this.pending = action
    if (!this.busy) void this.drain()
  }

  clear() {
    this.pending = null
  }

  private async drain() {
    this.busy = true
    try {
      while (this.pending) {
        const action = this.pending
        this.pending = null
        try {
          await action()
        } catch (error) {
          this.pending = null
          this.onError(error)
        }
      }
    } finally {
      this.busy = false
    }
  }
}
