/**
 * Flat captured-page slide overlay.
 *
 * Adapted from Readest's PageSlideRenderer (AGPL-3.0): one compositor
 * sheet, translate3d 1:1 with progress, clip to the reader cell.
 */

const EDGE_SHADOW_WIDTH_PX = 28

export class PageSlideRenderer {
  private sheet: HTMLDivElement | null = null
  private canvas: HTMLCanvasElement | null = null
  private shadow: HTMLDivElement | null = null
  private width = 0

  attach(container: HTMLElement, width: number, height: number, dpr = window.devicePixelRatio) {
    this.width = width
    container.style.overflow = 'hidden'
    const sheet = document.createElement('div')
    Object.assign(sheet.style, {
      position: 'absolute',
      inset: '0',
      width: `${width}px`,
      height: `${height}px`,
      pointerEvents: 'none',
      willChange: 'transform',
      backfaceVisibility: 'hidden',
      transform: 'translate3d(0px, 0, 0)',
    })
    const canvas = document.createElement('canvas')
    canvas.width = Math.round(width * dpr)
    canvas.height = Math.round(height * dpr)
    Object.assign(canvas.style, {
      position: 'absolute',
      inset: '0',
      width: `${width}px`,
      height: `${height}px`,
      pointerEvents: 'none',
    })
    const shadow = document.createElement('div')
    Object.assign(shadow.style, {
      position: 'absolute',
      top: '0',
      bottom: '0',
      width: `${EDGE_SHADOW_WIDTH_PX}px`,
      pointerEvents: 'none',
    })
    sheet.append(canvas, shadow)
    container.append(sheet)
    this.sheet = sheet
    this.canvas = canvas
    this.shadow = shadow
  }

  setTexture(source: CanvasImageSource) {
    const canvas = this.canvas
    const ctx = canvas?.getContext('2d')
    if (!canvas || !ctx) return
    ctx.drawImage(source, 0, 0, canvas.width, canvas.height)
  }

  render(progress: number, rtl = false) {
    if (!this.sheet) return
    const shift = (rtl ? 1 : -1) * progress * this.width
    this.sheet.style.transform = `translate3d(${shift}px, 0, 0)`
    if (!this.shadow) return
    const fade = Math.min(1, progress * 3) * (1 - progress)
    this.shadow.style.opacity = String(fade)
    this.shadow.style.left = rtl ? '0' : 'auto'
    this.shadow.style.right = rtl ? 'auto' : '0'
    this.shadow.style.background = rtl
      ? 'linear-gradient(to left, rgba(0,0,0,0.28), transparent)'
      : 'linear-gradient(to right, rgba(0,0,0,0.28), transparent)'
  }

  dispose() {
    this.sheet?.remove()
    this.sheet = null
    this.canvas = null
    this.shadow = null
  }
}
