export {}

declare global {
  interface FoliateViewElement extends HTMLElement {
    open: (book: File | string) => Promise<void>
    close: () => void
    init: (options: {
      lastLocation?: string | null
      showTextStart?: boolean
    }) => Promise<void>
    next: () => Promise<void> | void
    prev: () => Promise<void> | void
    goTo: (locator: string) => Promise<void>
    book?: {
      metadata?: { title?: unknown; author?: unknown }
    }
    lastLocation?: { cfi?: string; fraction?: number }
    renderer: { atStart: boolean; atEnd: boolean }
  }

  interface HTMLElementTagNameMap {
    'foliate-view': FoliateViewElement
  }
}
