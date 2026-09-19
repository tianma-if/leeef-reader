import { describe, expect, it } from 'vitest'
import { claimFromDelta, settleDuration, shouldCommitTurn, zoneOf } from './turnCommit'

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

describe('claimFromDelta', () => {
  it('claims a horizontal swipe from anywhere, not only the edge', () => {
    expect(claimFromDelta(-16, 2)).toBe('forward')
    expect(claimFromDelta(16, -3)).toBe('back')
  })

  it('locks vertical flicks so chrome toggle still works', () => {
    expect(claimFromDelta(2, -20)).toBe('vertical')
    expect(claimFromDelta(-4, 4)).toBe(null)
  })
})

describe('settleDuration', () => {
  it('scales with remaining travel and never goes below the floor', () => {
    expect(settleDuration(0, 1)).toBe(450)
    expect(settleDuration(0.9, 1)).toBeGreaterThanOrEqual(90)
    expect(settleDuration(0.99, 1)).toBe(90)
  })
})
