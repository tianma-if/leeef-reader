export {}

declare global {
  interface FoliateRendererElement extends HTMLElement {
    atStart: boolean
    atEnd: boolean
    setStyles?: (css: string | [string, string]) => void
    getContents?: () => { doc?: Document; index?: number; overlayer?: unknown }[]
    next?: (distance?: number) => void | Promise<void>
    prev?: (distance?: number) => void | Promise<void>
  }

  interface FoliateViewElement extends HTMLElement {
    open: (book: File | string) => Promise<void>
    close: () => void
    init: (options: {
      lastLocation?: string | null
      showTextStart?: boolean
    }) => Promise<void>
    next: () => Promise<void> | void
    prev: () => Promise<void> | void
    goTo: (locator: string | { fraction: number }) => Promise<unknown>
    goToFraction: (frac: number) => Promise<void>
    addAnnotation: (
      annotation: { value: string; color?: string },
      remove?: boolean,
    ) => Promise<unknown>
    deleteAnnotation: (annotation: { value: string }) => Promise<unknown>
    getCFI: (index: number, range?: Range | null) => string
    deselect: () => void
    book?: {
      metadata?: { title?: unknown; author?: unknown }
      toc?: TocItem[]
    }
    lastLocation?: {
      cfi?: string
      fraction?: number
      tocItem?: { label?: string }
      range?: Range
    }
    renderer: FoliateRendererElement
    search: (opts: { query: string }) => AsyncIterable<{ cfi?: string; excerpt?: string }>
  }

  type TocItem = { label?: unknown; href?: string; subitems?: TocItem[] }

  interface HTMLElementTagNameMap {
    'foliate-view': FoliateViewElement
  }
}
