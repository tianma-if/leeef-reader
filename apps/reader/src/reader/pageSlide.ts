/**
 * Flat captured-page slide overlay.
 *
 * Adapted from Readest's PageSlideRenderer (AGPL-3.0): one compositor
 * sheet, translate3d 1:1 with progress, clip to the reader cell.
 */

export class PageSlideRenderer {
  private sheet: HTMLDivElement | null = null
  private canvas: HTMLCanvasElement | null = null
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
    sheet.append(canvas)
    container.append(sheet)
    this.sheet = sheet
    this.canvas = canvas
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
  }

  dispose() {
    this.sheet?.remove()
    this.sheet = null
    this.canvas = null
  }
}
