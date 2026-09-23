import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import { CapturedPageTurn } from './capturedTurn'
import { captureWebviewRegion, probeWebviewReady, setCoverProgress, uncoverWebview } from './nativeCapture'

vi.mock('./nativeCapture', () => ({
  captureWebviewRegion: vi.fn(), probeWebviewReady: vi.fn(),
  setCoverProgress: vi.fn(), uncoverWebview: vi.fn(),
}))
vi.mock('./pageSlide', () => ({
  PageSlideRenderer: class {
    attach() {} setTexture() {} render() {} dispose() {}
    animateSettle() { return null }
  },
}))

const rect = { left: 0, top: 0, width: 400, height: 800 } as DOMRect
const navigate = vi.fn<(forward: boolean) => Promise<boolean>>()
const createTurner = () => new CapturedPageTurn({
  getHostElement: () => null, getContentRect: () => rect, navigate,
})
const capture = vi.mocked(captureWebviewRegion)
const probe = vi.mocked(probeWebviewReady)
const progress = vi.mocked(setCoverProgress)
const uncover = vi.mocked(uncoverWebview)
const flush = () => vi.advanceTimersByTimeAsync(100)

beforeEach(() => {
  vi.useFakeTimers()
  vi.resetAllMocks()
  vi.stubGlobal('navigator', { userAgent: 'Android' })
  vi.stubGlobal('requestAnimationFrame', (fn: FrameRequestCallback) =>
    setTimeout(() => fn(performance.now()), 16))
  vi.stubGlobal('cancelAnimationFrame', clearTimeout)
  capture.mockResolvedValue(new Uint8Array())
  probe.mockResolvedValue(true)
  progress.mockResolvedValue(undefined)
  uncover.mockResolvedValue(undefined)
  navigate.mockResolvedValue(true)
})

afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals() })

it('does not build an unused JS snapshot on Android', async () => {
  await createTurner().prepare()
  expect(capture).not.toHaveBeenCalled()
})

it('keeps the cover until native settle completes and refuses an overlapping drag', async () => {
  let finish!: () => void
  progress.mockImplementation((_value, _forward, duration) => duration
    ? new Promise<void>((resolve) => { finish = resolve }) : Promise.resolve())
  const turner = createTurner()
  const turning = turner.turn(true)
  await flush()
  expect(navigate.mock.calls).toEqual([[true]])
  expect(progress).toHaveBeenLastCalledWith(1, true, 280)
  expect(uncover).not.toHaveBeenCalled()
  expect(turner.startDrag(false)).toBe(false)
  finish()
  await turning
  expect(uncover).toHaveBeenCalledOnce()
})

it('coalesces fast pointer samples and allows only one progress IPC in flight', async () => {
  const turner = createTurner()
  turner.startDrag(true)
  await flush()
  progress.mockClear()
  let finish!: () => void
  progress.mockImplementationOnce(() => new Promise<void>((resolve) => { finish = resolve }))
  turner.setProgress(0.1)
  turner.setProgress(0.2)
  turner.setProgress(0.3)
  await vi.advanceTimersByTimeAsync(16)
  expect(progress.mock.calls).toEqual([[0.3, true]])
  turner.setProgress(0.4)
  turner.setProgress(0.6)
  await flush()
  expect(progress).toHaveBeenCalledOnce()
  finish()
  await flush()
  expect(progress.mock.calls).toEqual([[0.3, true], [0.6, true]])
  await turner.endDrag(true)
})

it('restores the original page under the cover before ending a cancelled swipe', async () => {
  const turner = createTurner()
  turner.startDrag(true)
  await flush()
  let ready!: (value: boolean) => void
  probe.mockImplementationOnce(() => new Promise((resolve) => { ready = resolve }))
  const ending = turner.endDrag(false)
  await flush()
  expect(navigate.mock.calls).toEqual([[true], [false]])
  expect(uncover).not.toHaveBeenCalled()
  ready(true)
  await flush()
  await ending
  expect(uncover).toHaveBeenCalledOnce()
})

it('does not navigate backwards when cancelling at the book boundary', async () => {
  navigate.mockResolvedValue(false)
  const turner = createTurner()
  turner.startDrag(true)
  await flush()
  expect(await turner.endDrag(false)).toBe(true)
  expect(navigate.mock.calls).toEqual([[true]])
  expect(uncover).toHaveBeenCalledOnce()
})

it('returns a safe plain-turn fallback when capture fails before navigation', async () => {
  capture.mockRejectedValue(new Error('capture unavailable'))
  expect(await createTurner().turn(true)).toBe(false)
  expect(navigate).not.toHaveBeenCalled()
})

it('does not request a second navigation after a failure following the page jump', async () => {
  probe.mockRejectedValue(new Error('bridge lost'))
  await expect(createTurner().turn(true)).rejects.toThrow('bridge lost')
  expect(navigate.mock.calls).toEqual([[true]])
  expect(uncover).toHaveBeenCalledOnce()
})

it('cleans up a late native capture after the reader closes without turning a page', async () => {
  let captured!: (bytes: Uint8Array<ArrayBuffer>) => void
  capture.mockImplementationOnce(() => new Promise((resolve) => { captured = resolve }))
  const turner = createTurner()
  const turning = turner.turn(true)
  turner.dispose()
  captured(new Uint8Array())
  expect(await turning).toBe(true)
  expect(navigate).not.toHaveBeenCalled()
  expect(uncover).toHaveBeenCalledOnce()
})

function iosTurner() {
  vi.stubGlobal('navigator', { userAgent: 'iPhone' })
  const overlays: { style: Record<string, string>; isConnected: boolean }[] = []
  const host = {
    isConnected: true,
    closest: () => ({ classList: { add() {}, remove() {} } }),
    getBoundingClientRect: () => rect,
    append: (overlay: typeof overlays[number]) => { overlays.push(overlay) },
  }
  vi.stubGlobal('document', { createElement: () => ({
    style: {}, dataset: {}, isConnected: true,
    remove() { this.isConnected = false },
  }) })
  vi.stubGlobal('createImageBitmap', vi.fn().mockResolvedValue({ close: vi.fn() }))
  return { overlays, turner: new CapturedPageTurn({
    getHostElement: () => host as unknown as HTMLElement, getContentRect: () => rect, navigate,
  }) }
}

it('reveals the incoming iOS page through a transparent overlay without a fixed pause', async () => {
  const { turner, overlays } = iosTurner()
  const turning = turner.turn(true)
  await vi.advanceTimersByTimeAsync(100)
  expect(navigate).toHaveBeenCalledOnce()
  expect(overlays[0]!.style.background).toBe('transparent')
  await vi.advanceTimersByTimeAsync(300)
  expect(await turning).toBe(true)
  expect(overlays[0]!.isConnected).toBe(false)
})

it('discards a warm screenshot invalidated while capture is still pending', async () => {
  const { turner, overlays } = iosTurner()
  let captured!: (bytes: Uint8Array<ArrayBuffer>) => void
  capture.mockImplementationOnce(() => new Promise((resolve) => { captured = resolve }))
  const preparing = turner.prepare()
  await flush()
  turner.invalidate()
  captured(new Uint8Array())
  await preparing
  expect(overlays).toHaveLength(0)
  const turning = turner.turn(true)
  await vi.advanceTimersByTimeAsync(500)
  await turning
  expect(capture).toHaveBeenCalledTimes(2)
})
