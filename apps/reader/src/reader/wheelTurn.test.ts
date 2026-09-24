import { expect, it } from 'vitest'
import { createWheelTurnState, wheelTurnDirection } from './wheelTurn'

const wheel = (deltaY: number, timeStamp: number, deltaX = 0, deltaMode = 0) =>
  ({ deltaY, timeStamp, deltaX, deltaMode })

it('turns down and up once per wheel burst', () => {
  const state = createWheelTurnState()
  expect(wheelTurnDirection(state, wheel(48, 0), 600)).toBe(true)
  expect(wheelTurnDirection(state, wheel(80, 20), 600)).toBeNull()
  expect(wheelTurnDirection(state, wheel(-48, 250), 600)).toBe(false)
})

it('accumulates small trackpad deltas without flipping on momentum', () => {
  const state = createWheelTurnState()
  expect(wheelTurnDirection(state, wheel(12, 0), 600)).toBeNull()
  expect(wheelTurnDirection(state, wheel(15, 20), 600)).toBeNull()
  expect(wheelTurnDirection(state, wheel(15, 40), 600)).toBe(true)
  expect(wheelTurnDirection(state, wheel(60, 100), 600)).toBeNull()
})

it('ignores horizontal gestures and supports line-based mouse wheels', () => {
  const state = createWheelTurnState()
  expect(wheelTurnDirection(state, wheel(10, 0, 20), 600)).toBeNull()
  expect(wheelTurnDirection(state, wheel(-3, 200, 0, 1), 600)).toBe(false)
})
