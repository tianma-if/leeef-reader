/**
 * Capture the outgoing page, jump the live iframe underneath, scrub the
 * overlay. Same pipeline as Readest #555 (AGPL-3.0): do not snapshot the
 * incoming page. Idle prepare mounts a near-invisible compositor surface
 * so the gesture's first frame is already a GPU texture.
 */
import { PageSlideRenderer } from './pageSlide'
import { captureWebviewRegion, type CaptureRect } from './nativeCapture'
import { settleDuration } from './turnCommit'

const waitForPaint = () =>
  new Promise<void>((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
  })

/** Zero-opacity layers are skipped by some mobile compositors. */
const PREPARED_SURFACE_WARM_OPACITY = '0.004'

type PreparedSurface = {
  overlay: HTMLDivElement
  renderer: PageSlideRenderer
  width: number
  height: number
  painted: boolean
}

type DragSession = {
  forward: boolean
  progress: number
  overlay: HTMLDivElement | null
  renderer: PageSlideRenderer | null
  ready: Promise<boolean>
  settled: boolean
}

export class CapturedPageTurn {
  private prepared: PreparedSurface | null = null
  private preparing: Promise<PreparedSurface | null> | null = null
  private drag: DragSession | null = null

  constructor(
    private readonly host: {
      getHostElement: () => HTMLElement | null
      getContentRect: () => DOMRect | null
      navigate: (forward: boolean) => Promise<void>
    },
  ) {}

  invalidate() {
    if (this.drag && !this.drag.settled) return
    this.closePrepared()
  }

  dispose() {
    this.disposeDrag()
    this.closePrepared()
  }

  async prepare() {
    if (this.drag && !this.drag.settled) return
    if (this.preparing) return
    const rect = this.host.getContentRect()
    if (this.prepared && rect && this.surfaceMatches(this.prepared, rect)) return
    const work = this.buildSurface(true)
    this.preparing = work
    try {
      const surface = await work
      if (this.drag && !this.drag.settled) return
      if (this.prepared && this.prepared !== surface) this.disposeSurface(this.prepared)
      this.prepared = surface
    } finally {
      if (this.preparing === work) this.preparing = null
    }
  }

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

  async turn(forward: boolean) {
    this.disposeDrag()
    this.startDrag(forward)
    const started = await this.endDrag(true)
    return started
  }

  private async setupDrag(session: DragSession) {
    let surface = this.takePrepared()
    if (!surface && this.preparing) {
      const pending = await this.preparing
      if (this.drag !== session) {
        if (pending) this.disposeSurface(pending)
        return false
      }
      surface = pending
      this.prepared = null
    }
    if (!surface) {
      surface = await this.buildSurface(false)
      if (this.drag !== session) {
        if (surface) this.disposeSurface(surface)
        return false
      }
    }
    if (!surface) return false
    session.overlay = surface.overlay
    session.renderer = surface.renderer
    surface.overlay.style.opacity = '1'
    surface.renderer.render(0, !session.forward)
    await waitForPaint()
    if (this.drag !== session) return false
    await this.host.navigate(session.forward)
    if (this.drag !== session) return false
    // Next page is already in the column strip; wait one paint so we never
    // scrub the overlay off a still-white iframe.
    await waitForPaint()
    if (this.drag !== session) return false
    surface.renderer.render(session.progress, !session.forward)
    return true
  }

  private async buildSurface(warm: boolean): Promise<PreparedSurface | null> {
    const hostElement = this.host.getHostElement()
    const rect = this.host.getContentRect()
    if (!hostElement || !rect || rect.width < 8 || rect.height < 8) return null
    const shell = hostElement.closest('.reader-shell')
    shell?.classList.add('is-capturing')
    await waitForPaint()
    let bytes: Uint8Array
    try {
      bytes = await captureWebviewRegion(this.toCaptureRect(rect))
    } catch {
      shell?.classList.remove('is-capturing')
      return null
    } finally {
      shell?.classList.remove('is-capturing')
    }
    const bitmap = await this.decode(bytes)
    if (!hostElement.isConnected) {
      bitmap.close()
      return null
    }
    const overlay = this.mountOverlay(hostElement, rect, warm)
    const renderer = new PageSlideRenderer()
    try {
      renderer.attach(overlay, rect.width, rect.height)
      renderer.setTexture(bitmap)
      renderer.render(0, false)
    } catch {
      renderer.dispose()
      overlay.remove()
      bitmap.close()
      return null
    } finally {
      bitmap.close()
    }
    const surface: PreparedSurface = {
      overlay,
      renderer,
      width: rect.width,
      height: rect.height,
      painted: false,
    }
    if (warm) {
      await waitForPaint()
      surface.painted = true
    }
    return surface
  }

  private takePrepared() {
    const rect = this.host.getContentRect()
    const surface = this.prepared
    this.prepared = null
    if (!surface || !rect || !this.surfaceMatches(surface, rect)) {
      if (surface) this.disposeSurface(surface)
      return null
    }
    return surface
  }

  private surfaceMatches(surface: PreparedSurface, rect: DOMRect) {
    return (
      surface.overlay.isConnected &&
      Math.abs(surface.width - rect.width) < 1 &&
      Math.abs(surface.height - rect.height) < 1
    )
  }

  private closePrepared() {
    if (this.prepared) this.disposeSurface(this.prepared)
    this.prepared = null
  }

  private disposeSurface(surface: PreparedSurface) {
    surface.renderer.dispose()
    surface.overlay.remove()
  }

  private disposeDrag() {
    const drag = this.drag
    this.drag = null
    if (!drag) return
    drag.settled = true
    if (drag.renderer || drag.overlay) {
      drag.renderer?.dispose()
      drag.overlay?.remove()
    }
  }

  private mountOverlay(host: HTMLElement, rect: DOMRect, warm: boolean) {
    const overlay = document.createElement('div')
    overlay.dataset.pageTurn = ''
    const hostRect = host.getBoundingClientRect()
    const paint = getComputedStyle(host.closest('.reader-shell') ?? host).backgroundColor
    Object.assign(overlay.style, {
      position: 'absolute',
      left: `${rect.left - hostRect.left}px`,
      top: `${rect.top - hostRect.top}px`,
      width: `${rect.width}px`,
      height: `${rect.height}px`,
      overflow: 'hidden',
      opacity: warm ? PREPARED_SURFACE_WARM_OPACITY : '0.01',
      zIndex: '50',
      pointerEvents: 'none',
      background: paint || 'transparent',
      transform: 'translateZ(0)',
      willChange: 'opacity',
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

  private animate(renderer: PageSlideRenderer, from: number, target: number, rtl: boolean) {
    const duration = settleDuration(from, target)
    const easing = (t: number) => 1 - (1 - t) ** 3
    const animation = renderer.animateSettle({ from, target, rtl, duration, easing })
    if (animation) {
      return new Promise<void>((resolve) => {
        const finish = () => {
          renderer.render(target, rtl)
          animation.cancel()
          resolve()
        }
        animation.onfinish = finish
        animation.oncancel = () => resolve()
      })
    }
    const start = performance.now()
    return new Promise<void>((resolve) => {
      const tick = (now: number) => {
        const t = Math.min(1, (now - start) / duration)
        renderer.render(from + (target - from) * easing(t), rtl)
        if (t < 1) requestAnimationFrame(tick)
        else resolve()
      }
      requestAnimationFrame(tick)
    })
  }
}
