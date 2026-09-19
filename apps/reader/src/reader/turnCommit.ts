export const EDGE_ZONE_RATIO = 0.18
export const CENTER_MIN = 0.375
export const CENTER_MAX = 0.625
export const COMMIT_PROGRESS = 0.5
export const FLICK_PROJECT_MS = 240
export const SETTLE_MS = 450
export const SETTLE_FLOOR_MS = 90
export const TAP_SLOP_PX = 12
export const CLAIM_DISTANCE_PX = 12
export const VERTICAL_LOCK_PX = 8

export type GestureClaim = 'forward' | 'back' | 'vertical' | null

export const claimFromDelta = (dx: number, dy: number): GestureClaim => {
  const absX = Math.abs(dx)
  const absY = Math.abs(dy)
  if (absY >= VERTICAL_LOCK_PX && absY > absX) return 'vertical'
  if (absX >= CLAIM_DISTANCE_PX && absX > absY) return dx < 0 ? 'forward' : 'back'
  return null
}

export type Zone = 'left' | 'center' | 'right'

export const zoneOf = (ratio: number): Zone => {
  if (ratio < CENTER_MIN) return 'left'
  if (ratio > CENTER_MAX) return 'right'
  return 'center'
}

export const shouldCommitTurn = (
  progress: number,
  velocityPxPerMs: number,
  width: number,
) => {
  if (width <= 0) return progress > COMMIT_PROGRESS
  const projected = progress + (velocityPxPerMs * FLICK_PROJECT_MS) / width
  return projected > COMMIT_PROGRESS
}

export const settleDuration = (from: number, target: number) =>
  Math.max(SETTLE_FLOOR_MS, SETTLE_MS * Math.abs(target - from))

export const releaseVelocity = (
  samples: { distance: number; time: number }[],
  now: number,
) => {
  const windowed = samples.filter((sample) => now - sample.time <= 90)
  if (windowed.length < 2) return 0
  const first = windowed[0]!
  const last = windowed[windowed.length - 1]!
  const dt = last.time - first.time
  if (dt <= 0) return 0
  return (last.distance - first.distance) / dt
}
