/**
 * Capture the outgoing page, jump the live iframe underneath, scrub the
 * overlay. Same pipeline as Readest #555 (AGPL-3.0): do not snapshot the
 * incoming page.
 */
import { PageSlideRenderer } from './pageSlide'
import { captureWebviewRegion, type CaptureRect } from './nativeCapture'
import { settleDuration } from './turnCommit'

const waitForPaint = () =>
  new Promise<void>((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
  })

type DragSession = {
  forward: boolean
  progress: number
  overlay: HTMLDivElement | null
  renderer: PageSlideRenderer | null
  ready: Promise<boolean>
  settled: boolean
}

export class CapturedPageTurn {
  private prepared: { bitmap: ImageBitmap; width: number; height: number } | null = null
  private drag: DragSession | null = null

  constructor(
    private readonly host: {
      getHostElement: () => HTMLElement | null
      getContentRect: () => DOMRect | null
      navigate: (forward: boolean) => Promise<void>
    },
  ) {}

  invalidate() {
    this.prepared?.bitmap.close()
    this.prepared = null
  }

  dispose() {
    this.disposeDrag()
    this.invalidate()
  }

  /** Kick off capture without waiting. Finger samples may arrive first. */
  startDrag(forward: boolean) {
    if (this.drag && !this.drag.settled) return
    this.disposeDrag()
    const session: DragSession = {
      forward,
      progress: 0,
      overlay: null,
      renderer: null,
      settled: false,
      ready: Promise.resolve(false),
    }
    this.drag = session
    session.ready = this.setupDrag(session)
  }

  setProgress(progress: number) {
    const drag = this.drag
    if (!drag) return
    drag.progress = Math.min(1, Math.max(0, progress))
    if (!drag.settled) drag.renderer?.render(drag.progress, !drag.forward)
  }

  /**
   * Waits for an in-flight capture before settling. Calling finish only after
   * beginDrag resolved left the overlay frozen mid-turn on slower phones.
   */
  async endDrag(complete: boolean) {
    const drag = this.drag
    if (!drag || drag.settled) return false
    drag.settled = true
    const started = await drag.ready
    if (!started || this.drag !== drag) {
      if (this.drag === drag) this.disposeDrag()
      return false
    }
    const target = complete ? 1 : 0
    if (drag.renderer) await this.animate(drag.renderer, drag.progress, target, !drag.forward)
    if (!complete) await this.host.navigate(!drag.forward)
    if (this.drag === drag) this.disposeDrag()
    return true
  }

  async prepare() {
    const rect = this.host.getContentRect()
    if (!rect || rect.width < 8 || rect.height < 8) return
    try {
      const bytes = await captureWebviewRegion(this.toCaptureRect(rect))
      const bitmap = await this.decode(bytes)
      this.invalidate()
      this.prepared = { bitmap, width: rect.width, height: rect.height }
    } catch {
      this.invalidate()
    }
  }

  async turn(forward: boolean) {
    this.disposeDrag()
    const hostElement = this.host.getHostElement()
    const rect = this.host.getContentRect()
    if (!hostElement || !rect) return false
    const overlay = this.mountOverlay(hostElement, rect)
    const renderer = new PageSlideRenderer()
    renderer.attach(overlay, rect.width, rect.height)
    try {
      const bitmap = await this.takeBitmap(rect)
      renderer.setTexture(bitmap)
      bitmap.close()
      overlay.style.opacity = '1'
      await waitForPaint()
      await this.host.navigate(forward)
      await this.animate(renderer, 0, 1, !forward)
    } finally {
      renderer.dispose()
      overlay.remove()
    }
    return true
  }

  private async setupDrag(session: DragSession) {
    const hostElement = this.host.getHostElement()
    const rect = this.host.getContentRect()
    if (!hostElement || !rect) return false
    const overlay = this.mountOverlay(hostElement, rect)
    const renderer = new PageSlideRenderer()
    renderer.attach(overlay, rect.width, rect.height)
    session.overlay = overlay
    session.renderer = renderer
    try {
      const bitmap = await this.takeBitmap(rect)
      if (this.drag !== session) {
        bitmap.close()
        renderer.dispose()
        overlay.remove()
        return false
      }
      renderer.setTexture(bitmap)
      bitmap.close()
      overlay.style.opacity = '1'
      renderer.render(session.progress, !session.forward)
      await waitForPaint()
      if (this.drag !== session) return false
      await this.host.navigate(session.forward)
      if (this.drag !== session) return false
      renderer.render(session.progress, !session.forward)
      return true
    } catch {
      renderer.dispose()
      overlay.remove()
      if (this.drag === session) {
        session.overlay = null
        session.renderer = null
      }
      return false
    }
  }

  private disposeDrag() {
    const drag = this.drag
    this.drag = null
    if (!drag) return
    drag.settled = true
    drag.renderer?.dispose()
    drag.overlay?.remove()
  }

  private async takeBitmap(rect: DOMRect) {
    const ready = this.prepared
    if (
      ready &&
      Math.abs(ready.width - rect.width) < 1 &&
      Math.abs(ready.height - rect.height) < 1
    ) {
      this.prepared = null
      return ready.bitmap
    }
    const bytes = await captureWebviewRegion(this.toCaptureRect(rect))
    return this.decode(bytes)
  }

  private mountOverlay(host: HTMLElement, rect: DOMRect) {
    const overlay = document.createElement('div')
    const hostRect = host.getBoundingClientRect()
    Object.assign(overlay.style, {
      position: 'absolute',
      left: `${rect.left - hostRect.left}px`,
      top: `${rect.top - hostRect.top}px`,
      width: `${rect.width}px`,
      height: `${rect.height}px`,
      opacity: '0.01',
      zIndex: '20',
      pointerEvents: 'none',
    })
    host.append(overlay)
    return overlay
  }

  private toCaptureRect(rect: DOMRect): CaptureRect {
    return { x: rect.left, y: rect.top, width: rect.width, height: rect.height }
  }

  private async decode(bytes: Uint8Array) {
    const copy = new Uint8Array(bytes.byteLength)
    copy.set(bytes)
    const blob = new Blob([copy], { type: 'image/jpeg' })
    return createImageBitmap(blob)
  }

  private animate(
    renderer: PageSlideRenderer,
    from: number,
    target: number,
    rtl: boolean,
  ) {
    const duration = settleDuration(from, target)
    const start = performance.now()
    return new Promise<void>((resolve) => {
      const tick = (now: number) => {
        const t = Math.min(1, (now - start) / duration)
        const eased = 1 - (1 - t) ** 3
        renderer.render(from + (target - from) * eased, rtl)
        if (t < 1) requestAnimationFrame(tick)
        else resolve()
      }
      requestAnimationFrame(tick)
    })
  }
}
