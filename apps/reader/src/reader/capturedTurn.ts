/**
 * Capture the outgoing page, jump the live iframe underneath, scrub the
 * overlay. Same pipeline as Readest #555 (AGPL-3.0): do not snapshot the
 * incoming page.
 */
import { PageSlideRenderer } from './pageSlide'
import { captureWebviewRegion, type CaptureRect } from './nativeCapture'

const waitForPaint = () =>
  new Promise<void>((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
  })

export class CapturedPageTurn {
  constructor(
    private readonly host: {
      getHostElement: () => HTMLElement | null
      getContentRect: () => DOMRect | null
      navigate: (forward: boolean) => Promise<void>
    },
  ) {}

  async turn(forward: boolean) {
    const hostElement = this.host.getHostElement()
    const rect = this.host.getContentRect()
    if (!hostElement || !rect) return false
    const overlay = this.mountOverlay(hostElement, rect)
    const renderer = new PageSlideRenderer()
    renderer.attach(overlay, rect.width, rect.height)
    try {
      const bytes = await captureWebviewRegion(this.toCaptureRect(rect))
      const bitmap = await this.decode(bytes)
      renderer.setTexture(bitmap)
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

  async beginDrag(forward: boolean) {
    const hostElement = this.host.getHostElement()
    const rect = this.host.getContentRect()
    if (!hostElement || !rect) return null
    const overlay = this.mountOverlay(hostElement, rect)
    const renderer = new PageSlideRenderer()
    renderer.attach(overlay, rect.width, rect.height)
    try {
      const bytes = await captureWebviewRegion(this.toCaptureRect(rect))
      const bitmap = await this.decode(bytes)
      renderer.setTexture(bitmap)
      overlay.style.opacity = '1'
      await waitForPaint()
      await this.host.navigate(forward)
    } catch (error) {
      renderer.dispose()
      overlay.remove()
      throw error
    }
    return {
      renderer,
      overlay,
      width: rect.width,
      forward,
      setProgress: (progress: number) => renderer.render(progress, !forward),
      finish: async (complete: boolean) => {
        const from = Number.parseFloat(overlay.dataset.progress ?? '0')
        const target = complete ? 1 : 0
        await this.animate(renderer, from, target, !forward)
        if (!complete) await this.host.navigate(!forward)
        renderer.dispose()
        overlay.remove()
      },
      overlayEl: overlay,
    }
  }

  private mountOverlay(host: HTMLElement, rect: DOMRect) {
    const overlay = document.createElement('div')
    Object.assign(overlay.style, {
      position: 'absolute',
      left: `${rect.left - host.getBoundingClientRect().left}px`,
      top: `${rect.top - host.getBoundingClientRect().top}px`,
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
    const duration = 280
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
