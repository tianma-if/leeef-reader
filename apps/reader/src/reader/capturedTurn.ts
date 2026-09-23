/**
 * Capture the outgoing page, jump the live iframe underneath, scrub the
 * overlay. Same pipeline as Readest #555 (AGPL-3.0): do not snapshot the
 * incoming page. Idle prepare mounts a near-invisible compositor surface
 * so the gesture's first frame is already a GPU texture.
 */
import { PageSlideRenderer } from './pageSlide'
import {
  captureWebviewRegion,
  probeWebviewReady,
  setCoverProgress,
  uncoverWebview,
  type CaptureRect,
} from './nativeCapture'
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
}

const isAndroid = () => /Android/i.test(navigator.userAgent)

type DragSession = {
  forward: boolean
  progress: number
  overlay: HTMLDivElement | null
  renderer: PageSlideRenderer | null
  ready: Promise<boolean>
  settled: boolean
  liveReady: boolean
  nativeCover: boolean
  moved: boolean
  progressFrame: number
  progressWork: Promise<unknown> | null
}

export class CapturedPageTurn {
  private prepared: PreparedSurface | null = null
  private preparing: Promise<PreparedSurface | null> | null = null
  private drag: DragSession | null = null
  private revision = 0

  constructor(
    private readonly host: {
      getHostElement: () => HTMLElement | null
      getContentRect: () => DOMRect | null
      navigate: (forward: boolean) => Promise<boolean>
    },
  ) {}

  invalidate() {
    this.revision++
    this.closePrepared()
  }

  dispose() {
    this.revision++
    void this.disposeDrag()
    this.closePrepared()
  }

  async prepare() {
    // Android uses the native bitmap directly; a warmed JS canvas is unused.
    if (isAndroid() || this.drag) return
    if (this.preparing) return this.preparing.then(() => undefined)
    const rect = this.host.getContentRect()
    if (this.prepared && rect && this.surfaceMatches(this.prepared, rect)) return
    const revision = this.revision
    const work = this.buildSurface(true, revision)
    this.preparing = work
    try {
      const surface = await work
      if (revision !== this.revision) {
        if (surface) this.disposeSurface(surface)
        return
      }
      if (this.prepared && this.prepared !== surface) this.disposeSurface(this.prepared)
      this.prepared = surface
    } finally {
      if (this.preparing === work) this.preparing = null
    }
  }

  startDrag(forward: boolean) {
    if (this.drag) return false
    const session: DragSession = {
      forward,
      progress: 0,
      overlay: null,
      renderer: null,
      settled: false,
      liveReady: false,
      nativeCover: false,
      moved: false,
      progressFrame: 0,
      progressWork: null,
      ready: Promise.resolve(false),
    }
    this.drag = session
    session.ready = this.setupDrag(session)
    // A setup failure may precede pointerup; keep it observed until endDrag.
    void session.ready.catch(() => undefined)
    return true
  }

  setProgress(progress: number) {
    const drag = this.drag
    if (!drag) return
    drag.progress = Math.min(1, Math.max(0, progress))
    if (drag.settled || !drag.liveReady || !drag.moved) return
    this.scheduleProgress(drag)
  }

  async endDrag(complete: boolean) {
    const drag = this.drag
    if (!drag || drag.settled) return false
    drag.settled = true
    cancelAnimationFrame(drag.progressFrame)
    try {
      const started = await drag.ready
      if (this.drag !== drag) return true // disposed: never retry navigation
      if (!started) return false // capture failed before navigation
      if (!drag.moved) return true // first/last page: no reverse navigation
      await drag.progressWork
      const target = complete ? 1 : 0
      if (drag.nativeCover) {
        await setCoverProgress(drag.progress, drag.forward)
        if (this.drag !== drag) return true
        await setCoverProgress(target, drag.forward, settleDuration(drag.progress, target))
      } else if (drag.renderer) {
        await this.animate(drag.renderer, drag.progress, target, !drag.forward)
      }
      if (this.drag !== drag) return true
      if (!complete) {
        await this.host.navigate(!drag.forward)
        await this.waitForLivePage(drag)
      }
      return true
    } finally {
      if (this.drag === drag) await this.disposeDrag()
    }
  }

  async turn(forward: boolean) {
    if (!this.startDrag(forward)) return true
    return this.endDrag(true)
  }

  private scheduleProgress(drag: DragSession) {
    if (drag.progressFrame || drag.progressWork) return
    drag.progressFrame = requestAnimationFrame(() => {
      drag.progressFrame = 0
      if (this.drag !== drag || drag.settled) return
      if (!drag.nativeCover) {
        drag.renderer?.render(drag.progress, !drag.forward)
        return
      }
      const sent = drag.progress
      // At most one IPC in flight; send the latest position, never old samples.
      drag.progressWork = setCoverProgress(sent, drag.forward).catch(() => undefined).finally(() => {
        drag.progressWork = null
        if (this.drag === drag && !drag.settled && drag.progress !== sent) this.scheduleProgress(drag)
      })
    })
  }

  private async setupDrag(session: DragSession) {
    if (isAndroid()) return this.setupNativeCover(session)
    let surface = this.takePrepared()
    if (!surface && this.preparing) {
      await this.preparing
      if (this.drag !== session) return false
      surface = this.takePrepared()
    }
    if (!surface) {
      surface = await this.buildSurface(false, this.revision)
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
    session.moved = await this.host.navigate(session.forward)
    if (this.drag !== session) return false
    await this.waitForLivePage(session)
    if (this.drag !== session) return false
    session.liveReady = true
    surface.renderer.render(session.moved ? session.progress : 0, !session.forward)
    return true
  }

  private async buildSurface(warm: boolean, revision: number): Promise<PreparedSurface | null> {
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
    if (revision !== this.revision) return null
    let bitmap: ImageBitmap
    try {
      bitmap = await this.decode(bytes)
    } catch {
      return null
    }
    if (!hostElement.isConnected || revision !== this.revision) {
      bitmap.close()
      return null
    }
    const overlay = this.mountOverlay(hostElement, rect, warm)
    const renderer = new PageSlideRenderer()
    try {
      // Native snapshots are capped at 2x. Keep that resolution instead of
      // allocating and uploading an upscaled 3x canvas on high-density phones.
      renderer.attach(overlay, rect.width, rect.height, bitmap.width / rect.width)
      renderer.setTexture(bitmap)
      renderer.render(0, false)
    } catch {
      renderer.dispose()
      overlay.remove()
      return null
    } finally {
      bitmap.close()
    }
    const surface: PreparedSurface = {
      overlay,
      renderer,
      width: rect.width,
      height: rect.height,
    }
    if (warm) {
      await waitForPaint()
      if (revision !== this.revision) {
        this.disposeSurface(surface)
        return null
      }
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

  private async disposeDrag() {
    const drag = this.drag
    this.drag = null
    if (!drag) return
    drag.settled = true
    cancelAnimationFrame(drag.progressFrame)
    await drag.progressWork
    if (drag.nativeCover) await uncoverWebview().catch(() => undefined)
    if (drag.renderer || drag.overlay) {
      drag.renderer?.dispose()
      drag.overlay?.remove()
    }
  }

  private mountOverlay(host: HTMLElement, rect: DOMRect, warm: boolean) {
    const overlay = document.createElement('div')
    overlay.dataset.pageTurn = ''
    const hostRect = host.getBoundingClientRect()
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
      // Only the moving sheet is opaque; the incoming live page must show
      // through the space it vacates.
      background: 'transparent',
      transform: 'translateZ(0)',
      willChange: 'opacity',
    })
    host.append(overlay)
    return overlay
  }

  private toCaptureRect(rect: DOMRect): CaptureRect {
    return { x: rect.left, y: rect.top, width: rect.width, height: rect.height }
  }

  private async setupNativeCover(session: DragSession) {
    const rect = this.host.getContentRect()
    if (!rect || rect.width < 8 || rect.height < 8) return false
    try {
      await captureWebviewRegion(this.toCaptureRect(rect), true)
    } catch {
      return false
    }
    if (this.drag !== session) {
      await uncoverWebview().catch(() => undefined)
      return false
    }
    session.nativeCover = true
    session.moved = await this.host.navigate(session.forward)
    if (this.drag !== session) return false
    await this.waitForLivePage(session)
    if (this.drag !== session) return false
    await setCoverProgress(session.moved ? session.progress : 0, session.forward)
    session.liveReady = true
    if (!session.settled && session.moved) this.scheduleProgress(session)
    return true
  }

  private async waitForLivePage(session: DragSession) {
    if (this.drag !== session) return
    if (session.nativeCover) await probeWebviewReady()
    // Navigation has completed layout. Let the new page reach the compositor
    // before exposing it, without a fixed 420ms pause on every iOS turn.
    await waitForPaint()
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
