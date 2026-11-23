import { releaseVelocity, shouldCommitTurn, TAP_SLOP_PX } from './turnCommit'
import {
  createTurnGestureIntent,
  edgeDirectionOf,
  shouldClaimTurnGesture,
  TURN_FAST_CLAIM_DISTANCE_PX,
} from './turnGestureArena'

// Leave a stationary touch to the WebView before it starts native text selection.
const SWIPE_START_WINDOW_MS = 350

type TouchOptions = {
  signal: AbortSignal
  host: HTMLElement
  frame?: HTMLElement
  paginated: () => boolean
  selecting: () => boolean
  prepareTurn: () => void
  startTurn: (forward: boolean) => boolean
  moveTurn: (progress: number) => void
  finishTurn: (forward: boolean, captured: boolean, commit: boolean) => void
  showChrome: () => void
}

export function bindReaderTouch(target: EventTarget, options: TouchOptions) {
  let ignoreClick = false
  let gesture: {
    id: number
    x: number
    y: number
    width: number
    startedAt: number
    selecting: boolean
    paginated: boolean
    claimed: boolean
    captured: boolean
    forward: boolean
    visualOrigin: number
    intent: ReturnType<typeof createTurnGestureIntent>
    samples: { distance: number; time: number }[]
  } | null = null
  const listen = <K extends keyof GlobalEventHandlersEventMap>(
    type: K,
    callback: (event: GlobalEventHandlersEventMap[K]) => void,
    settings?: AddEventListenerOptions,
  ) => target.addEventListener(type, callback as EventListener, { signal: options.signal, ...settings })
  const progressOf = (distance: number, origin: number, width: number) =>
    Math.min(1, Math.max(0, (distance - origin) / width))

  listen('touchstart', (event) => {
    ignoreClick = false
    if (gesture) {
      if (event.touches.length > 1) gesture.selecting = true
      return
    }
    const touch = event.changedTouches[0]
    const bounds = options.host.getBoundingClientRect()
    if (!touch || event.touches.length !== 1 || !bounds.width) return
    const frame = options.frame
    const frameRect = frame?.getBoundingClientRect()
    const scale = frameRect && frame?.clientWidth ? frameRect.width / frame.clientWidth : 1
    const x = (frameRect?.left ?? 0) + touch.clientX * scale - bounds.left
    const now = performance.now()
    gesture = {
      id: touch.identifier,
      x: touch.screenX,
      y: touch.screenY,
      width: bounds.width,
      startedAt: now,
      selecting: options.selecting(),
      paginated: options.paginated(),
      claimed: false,
      captured: false,
      forward: true,
      visualOrigin: 0,
      intent: createTurnGestureIntent(edgeDirectionOf(x, bounds.width), now),
      samples: [{ distance: 0, time: now }],
    }
    if (gesture.paginated && !gesture.selecting) options.prepareTurn()
  }, { passive: true })

  listen('touchmove', (event) => {
    const drag = gesture
    if (!drag || !drag.paginated || drag.selecting || event.touches.length !== 1) return
    const touch = Array.from(event.changedTouches).find((item) => item.identifier === drag.id)
    if (!touch) return
    const dx = touch.screenX - drag.x
    const dy = touch.screenY - drag.y
    const now = performance.now()
    if (!drag.claimed) {
      if (options.selecting() || now - drag.startedAt >= SWIPE_START_WINDOW_MS) {
        drag.selecting = true
        return
      }
      const wantsTurn = shouldClaimTurnGesture(drag.intent, { deltaX: dx, deltaY: dy, deltaT: now })
      if (!wantsTurn || Math.abs(dx) < TURN_FAST_CLAIM_DISTANCE_PX) return
      drag.claimed = true
      drag.forward = dx < 0
      drag.visualOrigin = Math.abs(dx)
      drag.captured = options.startTurn(drag.forward)
    }
    event.preventDefault()
    const distance = drag.forward ? -dx : dx
    if (drag.captured) options.moveTurn(progressOf(distance, drag.visualOrigin, drag.width))
    drag.samples.push({ distance, time: now })
    if (drag.samples.length > 8) drag.samples.shift()
  }, { passive: false })

  const finish = (event: TouchEvent) => {
    const drag = gesture
    if (!drag) return
    const touch = Array.from(event.changedTouches).find((item) => item.identifier === drag.id)
    if (!touch && event.type !== 'touchcancel') return
    gesture = null
    const dx = (touch?.screenX ?? drag.x) - drag.x
    const dy = (touch?.screenY ?? drag.y) - drag.y
    const now = performance.now()
    const cancelled = event.type === 'touchcancel'
    if (drag.claimed) {
      ignoreClick = true
      const distance = drag.forward ? -dx : dx
      const progress = progressOf(distance, drag.captured ? drag.visualOrigin : 0, drag.width)
      if (drag.captured) options.moveTurn(progress)
      const velocity = releaseVelocity(drag.samples, now)
      const commit = !cancelled && !drag.selecting && shouldCommitTurn(progress, velocity, drag.width)
      options.finishTurn(drag.forward, drag.captured, commit)
      return
    }
    if (cancelled || options.selecting() || now - drag.startedAt >= SWIPE_START_WINDOW_MS) {
      ignoreClick = true
      return
    }
    ignoreClick = Math.hypot(dx, dy) > TAP_SLOP_PX
    if (!drag.selecting && dy < -10 && Math.abs(dy) > 2 * Math.abs(dx) && Math.abs(dx) < drag.width * 0.3) {
      ignoreClick = true
      options.showChrome()
    }
  }
  listen('touchend', finish, { passive: true })
  listen('touchcancel', finish, { passive: true })
  listen('pointerdown', (event) => {
    if (event.pointerType === 'mouse') ignoreClick = false
  })
  listen('click', (event) => {
    if (!ignoreClick) return
    ignoreClick = false
    // Native selection handles can consume the original touch sequence themselves.
    event.preventDefault()
    event.stopImmediatePropagation()
  }, { capture: true })
}
