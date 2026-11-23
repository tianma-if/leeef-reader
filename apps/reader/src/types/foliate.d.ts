export {}

declare global {
  interface FoliateRendererElement extends HTMLElement {
    atStart: boolean
    atEnd: boolean
    readonly page?: number
    readonly pages?: number
    setStyles?: (css: string | [string, string]) => void
    getContents?: () => {
      doc?: Document
      index?: number
      overlayer?: { hitTest: (event: MouseEvent) => [] | [string, Range] }
    }[]
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
      tocItem?: TocItem
      range?: Range
    }
    renderer: FoliateRendererElement
    search: (opts: { query: string }) => AsyncIterable<FoliateSearchResult>
    clearSearch: () => void
  }

  type TocItem = { id?: number; label?: unknown; href?: string; subitems?: TocItem[] }
  type FoliateSearchExcerpt = { pre: string; match: string; post: string }
  type FoliateSearchMatch = { cfi: string; excerpt: FoliateSearchExcerpt }
  type FoliateSearchResult = FoliateSearchMatch
    | { label: string; subitems: FoliateSearchMatch[] }
    | { progress: number }
    | 'done'

  interface HTMLElementTagNameMap {
    'foliate-view': FoliateViewElement
  }
}
