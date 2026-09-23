/**
 * Flat captured-page slide overlay.
 *
 * Adapted from Readest's PageSlideRenderer (AGPL-3.0): one compositor
 * sheet, translate3d 1:1 with progress, clip to the reader cell. Settle
 * uses Web Animations so the play-out runs on the compositor.
 */

const EDGE_SHADOW_WIDTH_PX = 28
const SETTLE_KEYFRAME_STEPS = 32

export type PageSlideSettleOptions = {
  from: number
  target: number
  rtl: boolean
  duration: number
  easing: (progress: number) => number
}

export class PageSlideRenderer {
  private sheet: HTMLDivElement | null = null
  private canvas: HTMLCanvasElement | null = null
  private shadow: HTMLDivElement | null = null
  private width = 0
  private shadowRtl: boolean | null = null

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
      background: 'inherit',
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
    this.updateShadow(false)
  }

  setTexture(source: CanvasImageSource) {
    const canvas = this.canvas
    const ctx = canvas?.getContext('2d')
    if (!canvas || !ctx) return
    ctx.drawImage(source, 0, 0, canvas.width, canvas.height)
  }

  render(progress: number, rtl = false) {
    if (!this.sheet) return
    this.updateShadow(rtl)
    this.sheet.style.transform = this.transformAt(progress, rtl)
  }

  animateSettle(options: PageSlideSettleOptions): Animation | null {
    const sheet = this.sheet
    if (!sheet || typeof sheet.animate !== 'function') return null
    this.updateShadow(options.rtl)
    const span = options.target - options.from
    const keyframes = Array.from({ length: SETTLE_KEYFRAME_STEPS + 1 }, (_, index) => {
      const offset = index / SETTLE_KEYFRAME_STEPS
      const progress = options.from + span * options.easing(offset)
      return { offset, transform: this.transformAt(progress, options.rtl) }
    })
    try {
      return sheet.animate(keyframes, {
        duration: options.duration,
        easing: 'linear',
        fill: 'both',
      })
    } catch {
      return null
    }
  }

  dispose() {
    this.sheet?.getAnimations().forEach((animation) => animation.cancel())
    this.sheet?.remove()
    this.sheet = null
    this.canvas = null
    this.shadow = null
    this.shadowRtl = null
  }

  private transformAt(progress: number, rtl: boolean) {
    const shift = (rtl ? 1 : -1) * progress * this.width
    return `translate3d(${shift}px, 0, 0)`
  }

  private updateShadow(rtl: boolean) {
    const shadow = this.shadow
    if (!shadow || this.shadowRtl === rtl) return
    this.shadowRtl = rtl
    if (rtl) {
      shadow.style.left = `${-EDGE_SHADOW_WIDTH_PX}px`
      shadow.style.right = 'auto'
      shadow.style.background = 'linear-gradient(to right, transparent, rgba(0, 0, 0, 0.35))'
    } else {
      shadow.style.left = '100%'
      shadow.style.right = 'auto'
      shadow.style.background = 'linear-gradient(to right, rgba(0, 0, 0, 0.35), transparent)'
    }
  }
}
