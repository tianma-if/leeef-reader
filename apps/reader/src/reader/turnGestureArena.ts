/**
 * Gesture claim arena for captured-slide.
 *
 * Adapted from Readest turnGestureArena (AGPL-3.0): edge swipes claim on
 * the first inward sample; center swipes need two coherent 6px samples;
 * everything else waits for the 15px fallback.
 */

export type TurnGestureDirection = -1 | 0 | 1

export type TurnGestureIntent = {
  edgeDirection: TurnGestureDirection
  lastDeltaX: number
  lastDeltaY: number
  lastSampleTime: number
  horizontalSign: TurnGestureDirection
  horizontalStreak: number
  verticalLocked: boolean
}

export const TURN_EDGE_ZONE_RATIO = 0.18
export const TURN_FAST_CLAIM_DISTANCE_PX = 6
export const TURN_FAST_CLAIM_MAX_SAMPLE_GAP_MS = 80
export const TURN_VERTICAL_LOCK_DISTANCE_PX = 8
export const TURN_DIRECTION_DOMINANCE = 1.5
export const TURN_FALLBACK_DISTANCE_PX = 15

export const createTurnGestureIntent = (
  edgeDirection: TurnGestureDirection,
  startTime: number,
): TurnGestureIntent => ({
  edgeDirection,
  lastDeltaX: 0,
  lastDeltaY: 0,
  lastSampleTime: startTime,
  horizontalSign: 0,
  horizontalStreak: 0,
  verticalLocked: false,
})

export const edgeDirectionOf = (localStartX: number, width: number): TurnGestureDirection => {
  if (width <= 0) return 0
  if (localStartX >= 0 && localStartX <= width * TURN_EDGE_ZONE_RATIO) return 1
  if (localStartX <= width && localStartX >= width * (1 - TURN_EDGE_ZONE_RATIO)) return -1
  return 0
}

export const shouldClaimTurnGesture = (
  intent: TurnGestureIntent,
  sample: { deltaX: number; deltaY: number; deltaT: number },
  fallbackDistance = TURN_FALLBACK_DISTANCE_PX,
) => {
  if (intent.verticalLocked) return false

  const { deltaX, deltaY, deltaT } = sample
  const stepX = deltaX - intent.lastDeltaX
  const stepY = deltaY - intent.lastDeltaY
  const sampleGap = deltaT - intent.lastSampleTime
  intent.lastDeltaX = deltaX
  intent.lastDeltaY = deltaY
  intent.lastSampleTime = deltaT

  const absX = Math.abs(deltaX)
  const absY = Math.abs(deltaY)
  if (absY >= TURN_VERTICAL_LOCK_DISTANCE_PX && absY > absX) {
    intent.verticalLocked = true
    intent.horizontalStreak = 0
    intent.horizontalSign = 0
    return false
  }

  const stepSign = Math.sign(stepX) as TurnGestureDirection
  const timelySample = sampleGap >= 0 && sampleGap <= TURN_FAST_CLAIM_MAX_SAMPLE_GAP_MS
  const horizontalSample =
    Math.abs(stepX) >= 1 && Math.abs(stepX) > Math.abs(stepY) * TURN_DIRECTION_DOMINANCE
  if (horizontalSample) {
    intent.horizontalStreak =
      timelySample && stepSign === intent.horizontalSign ? intent.horizontalStreak + 1 : 1
    intent.horizontalSign = stepSign
  } else {
    intent.horizontalStreak = 0
    intent.horizontalSign = 0
  }

  const edgeFastPath =
    intent.edgeDirection !== 0 &&
    Math.sign(deltaX) === intent.edgeDirection &&
    absX > absY * TURN_DIRECTION_DOMINANCE
  const coherentFastPath =
    intent.edgeDirection === 0 &&
    absX >= TURN_FAST_CLAIM_DISTANCE_PX &&
    intent.horizontalStreak >= 2 &&
    absX > absY * TURN_DIRECTION_DOMINANCE
  const fallback = absX >= fallbackDistance && absX > absY
  return edgeFastPath || coherentFastPath || fallback
}
