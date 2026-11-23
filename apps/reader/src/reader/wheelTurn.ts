export type WheelTurnState = {
  lastTime: number
  distance: number
  consumed: boolean
}

const WHEEL_GESTURE_GAP_MS = 180
const WHEEL_TURN_DISTANCE_PX = 40

export const createWheelTurnState = (): WheelTurnState => ({
  lastTime: -Infinity,
  distance: 0,
  consumed: false,
})

/** Return at most one page turn for each burst of vertical wheel input. */
export const wheelTurnDirection = (
  state: WheelTurnState,
  event: Pick<WheelEvent, 'deltaX' | 'deltaY' | 'deltaMode' | 'timeStamp'>,
  pageHeight: number,
): boolean | null => {
  if (event.timeStamp - state.lastTime > WHEEL_GESTURE_GAP_MS) {
    state.distance = 0
    state.consumed = false
  }
  state.lastTime = event.timeStamp

  const multiplier = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? pageHeight : 1
  const x = event.deltaX * multiplier
  const y = event.deltaY * multiplier
  const dominant = Math.abs(x) > Math.abs(y) ? x : y
  if (!Number.isFinite(dominant) || dominant === 0) return null
  if (state.consumed) return null
  if (Math.sign(dominant) !== Math.sign(state.distance)) state.distance = 0
  state.distance += dominant
  if (Math.abs(state.distance) < WHEEL_TURN_DISTANCE_PX) return null
  state.consumed = true
  return state.distance > 0
}
