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
      toc?: TocItem[]
    }
    lastLocation?: { cfi?: string; fraction?: number; tocItem?: { label?: string } }
    renderer: { atStart: boolean; atEnd: boolean }
    search: (opts: { query: string }) => AsyncIterable<{ cfi?: string; excerpt?: string }>
  }

  type TocItem = { label?: unknown; href?: string; subitems?: TocItem[] }

  interface HTMLElementTagNameMap {
    'foliate-view': FoliateViewElement
  }
}
