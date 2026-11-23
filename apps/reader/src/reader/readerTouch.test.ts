import { afterEach, describe, expect, it, vi } from 'vitest'
import { bindReaderTouch } from './readerTouch'

const setup = (selecting = () => false) => {
  const target = new EventTarget()
  const controller = new AbortController()
  let now = 0
  vi.spyOn(performance, 'now').mockImplementation(() => now)
  const startTurn = vi.fn(() => true)
  const moveTurn = vi.fn()
  const finishTurn = vi.fn()
  bindReaderTouch(target, {
    signal: controller.signal,
    host: { getBoundingClientRect: () => ({ left: 0, width: 400 }) } as HTMLElement,
    paginated: () => true,
    selecting,
    prepareTurn: vi.fn(),
    startTurn,
    moveTurn,
    finishTurn,
    showChrome: vi.fn(),
  })
  const touch = (type: string, x: number, time: number) => {
    now = time
    const point = { identifier: 1, screenX: x, screenY: 100, clientX: x }
    const event = Object.assign(new Event(type, { cancelable: true }), {
      touches: type === 'touchend' || type === 'touchcancel' ? [] : [point],
      changedTouches: [point],
    })
    return target.dispatchEvent(event)
  }
  const click = () => target.dispatchEvent(new Event('click', { cancelable: true }))
  return { touch, click, startTurn, moveTurn, finishTurn }
}

afterEach(() => vi.restoreAllMocks())

describe('reader touch gestures', () => {
  it('leaves a long press and subsequent movement to native selection', () => {
    const { touch, click, startTurn } = setup()
    expect(touch('touchstart', 375, 0)).toBe(true)
    expect(touch('touchmove', 373, 20)).toBe(true)
    expect(touch('touchmove', 270, 500)).toBe(true)
    expect(touch('touchend', 270, 550)).toBe(true)
    expect(startTurn).not.toHaveBeenCalled()
    expect(click()).toBe(false)
  })

  it('does not steal drags from a selection that appears during the touch', () => {
    let selected = false
    const { touch, startTurn } = setup(() => selected)
    touch('touchstart', 320, 0)
    selected = true
    expect(touch('touchmove', 260, 100)).toBe(true)
    expect(startTurn).not.toHaveBeenCalled()
  })

  it('commits a horizontal page turn and suppresses the resulting tap', () => {
    const { touch, click, startTurn, finishTurn } = setup()
    touch('touchstart', 320, 0)
    expect(touch('touchmove', 280, 30)).toBe(false)
    touch('touchmove', 180, 55)
    touch('touchend', 50, 70)
    expect(startTurn).toHaveBeenCalledWith(true)
    expect(finishTurn).toHaveBeenCalledWith(true, true, true)
    expect(click()).toBe(false)
    touch('touchstart', 50, 100)
    touch('touchend', 50, 150)
    expect(click()).toBe(true)
  })

  it('rolls back a captured turn when the WebView cancels the touch', () => {
    const { touch, finishTurn } = setup()
    touch('touchstart', 320, 0)
    touch('touchmove', 280, 30)
    touch('touchcancel', 50, 60)
    expect(finishTurn).toHaveBeenCalledWith(true, true, false)
  })
})
