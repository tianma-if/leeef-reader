import { afterEach, describe, expect, it, vi } from 'vitest'
import { bindReaderTouch } from './readerTouch'

const setup = (selecting = () => false, paginated = () => true) => {
  const target = new EventTarget()
  const controller = new AbortController()
  let now = 0
  vi.spyOn(performance, 'now').mockImplementation(() => now)
  const startTurn = vi.fn(() => true)
  const moveTurn = vi.fn()
  const finishTurn = vi.fn()
  const previewBookmark = vi.fn()
  const addBookmark = vi.fn()
  const showChrome = vi.fn()
  bindReaderTouch(target, {
    signal: controller.signal,
    host: { getBoundingClientRect: () => ({ left: 0, width: 400 }) } as HTMLElement,
    paginated,
    selecting,
    prepareTurn: vi.fn(),
    startTurn,
    moveTurn,
    finishTurn,
    canPullBookmark: () => true,
    previewBookmark,
    addBookmark,
    showChrome,
  })
  const touch = (type: string, x: number, time: number, y = 100, fingers = 1, cancelable = true) => {
    now = time
    const point = { identifier: 1, screenX: x, screenY: y, clientX: x, clientY: y }
    const event = Object.assign(new Event(type, { cancelable }), {
      touches: type === 'touchend' || type === 'touchcancel' ? [] : Array(fingers).fill(point),
      changedTouches: [point],
    })
    return target.dispatchEvent(event)
  }
  const click = () => target.dispatchEvent(new Event('click', { cancelable: true }))
  return { touch, click, startTurn, moveTurn, finishTurn, previewBookmark, addBookmark, showChrome }
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

  it('previews a downward pull and adds the bookmark on release without turning or tapping', () => {
    const { touch, click, startTurn, previewBookmark, addBookmark, showChrome } = setup()
    touch('touchstart', 150, 0)
    expect(touch('touchmove', 150, 30, 117)).toBe(false)
    expect(previewBookmark).toHaveBeenLastCalledWith('pulling')
    touch('touchmove', 157, 60, 180)
    expect(previewBookmark).toHaveBeenLastCalledWith('ready')
    expect(addBookmark).not.toHaveBeenCalled()
    touch('touchend', 157, 500, 180)
    expect(previewBookmark).toHaveBeenLastCalledWith(null)
    expect(addBookmark).toHaveBeenCalledTimes(1)
    expect(startTurn).not.toHaveBeenCalled()
    expect(showChrome).not.toHaveBeenCalled()
    expect(click()).toBe(false)
  })

  it('accepts a completed pull when the WebView delivers non-cancelable move events', () => {
    const { touch, addBookmark } = setup()
    touch('touchstart', 150, 0)
    touch('touchmove', 150, 25, 108, 1, false)
    touch('touchmove', 150, 60, 180, 1, false)
    touch('touchend', 150, 80, 180)
    expect(addBookmark).toHaveBeenCalledTimes(1)
  })

  it.each(['short pull', 'reversed pull', 'cancelled pull', 'second finger', 'text selection'])(
    'discards the preview after a %s',
    (kind) => {
      let selected = false
      const { touch, previewBookmark, addBookmark } = setup(() => selected)
      touch('touchstart', 150, 0)
      touch('touchmove', 150, 30, kind === 'short pull' ? 135 : 180)
      if (kind === 'second finger') touch('touchstart', 150, 50, 180, 2)
      if (kind === 'text selection') selected = true
      const endType = kind === 'cancelled pull' ? 'touchcancel' : 'touchend'
      touch(endType, 150, 60, kind === 'short pull' || kind === 'reversed pull' ? 135 : 180)
      expect(previewBookmark).toHaveBeenLastCalledWith(null)
      expect(addBookmark).not.toHaveBeenCalled()
    },
  )

  it.each([
    { paginated: false, startY: 100, startTime: 20 },
    { paginated: true, startY: 10, startTime: 20 },
    { paginated: true, startY: 100, startTime: 400 },
  ])('leaves an ineligible downward motion to the WebView (%o)', ({ paginated, startY, startTime }) => {
    const { touch, previewBookmark, addBookmark } = setup(() => false, () => paginated)
    touch('touchstart', 150, 0, startY)
    expect(touch('touchmove', 150, startTime, startY + 85)).toBe(true)
    touch('touchend', 150, startTime + 20, startY + 85)
    expect(previewBookmark).not.toHaveBeenCalled()
    expect(addBookmark).not.toHaveBeenCalled()
  })

  it('still opens the reader controls on an upward swipe', () => {
    const { touch, addBookmark, showChrome } = setup()
    touch('touchstart', 150, 0)
    touch('touchmove', 150, 30, 60)
    touch('touchend', 150, 50, 45)
    expect(showChrome).toHaveBeenCalledTimes(1)
    expect(addBookmark).not.toHaveBeenCalled()
  })
})
