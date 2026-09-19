import { describe, expect, it } from 'vitest'
import { settleDuration, shouldCommitTurn, zoneOf } from './turnCommit'
import {
  createTurnGestureIntent,
  shouldClaimTurnGesture,
} from './turnGestureArena'

describe('zoneOf', () => {
  it('splits the page into edge turn and center chrome', () => {
    expect(zoneOf(0.1)).toBe('left')
    expect(zoneOf(0.5)).toBe('center')
    expect(zoneOf(0.9)).toBe('right')
  })
})

describe('shouldCommitTurn', () => {
  it('commits past halfway', () => {
    expect(shouldCommitTurn(0.6, 0, 400)).toBe(true)
    expect(shouldCommitTurn(0.2, 0, 400)).toBe(false)
  })

  it('commits a short flick that would pass halfway', () => {
    expect(shouldCommitTurn(0.3, 0.5, 400)).toBe(true)
    expect(shouldCommitTurn(0.2, 0.05, 400)).toBe(false)
  })
})

describe('shouldClaimTurnGesture', () => {
  it('claims a center swipe after two coherent horizontal samples', () => {
    const intent = createTurnGestureIntent(0, 0)
    expect(shouldClaimTurnGesture(intent, { deltaX: -4, deltaY: 0, deltaT: 10 })).toBe(false)
    expect(shouldClaimTurnGesture(intent, { deltaX: -8, deltaY: 0, deltaT: 20 })).toBe(true)
  })

  it('claims an inward edge swipe on the first sample', () => {
    const intent = createTurnGestureIntent(-1, 0)
    expect(shouldClaimTurnGesture(intent, { deltaX: -3, deltaY: 0, deltaT: 8 })).toBe(true)
  })

  it('locks vertical flicks so chrome toggle still works', () => {
    const intent = createTurnGestureIntent(0, 0)
    expect(shouldClaimTurnGesture(intent, { deltaX: 2, deltaY: -20, deltaT: 16 })).toBe(false)
    expect(intent.verticalLocked).toBe(true)
    expect(shouldClaimTurnGesture(intent, { deltaX: -20, deltaY: -20, deltaT: 30 })).toBe(false)
  })
})

describe('settleDuration', () => {
  it('scales with remaining travel and never goes below the floor', () => {
    expect(settleDuration(0, 1)).toBe(450)
    expect(settleDuration(0.9, 1)).toBeGreaterThanOrEqual(90)
    expect(settleDuration(0.99, 1)).toBe(90)
  })
})
