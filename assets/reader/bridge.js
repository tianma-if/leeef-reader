import '../foliate-js/view.js'

const view = document.querySelector('#reader')
let currentBookURL
let selectionTimer

const send = (type, payload = {}) => {
    const bridge = globalThis.flutter_inappwebview
    if (!bridge?.callHandler) return Promise.resolve()
    return bridge.callHandler('readerEvent', { type, ...payload })
}

const localizedText = value => {
    if (typeof value === 'string') return value
    if (Array.isArray(value)) return localizedText(value[0])
    if (value && typeof value === 'object')
        return localizedText(value[document.documentElement.lang])
            ?? localizedText(Object.values(value)[0])
    return null
}

const serializeTOC = items => (items ?? []).map(item => ({
    label: localizedText(item.label) ?? '',
    href: String(item.href ?? ''),
    children: serializeTOC(item.subitems),
}))

const serializeMetadata = book => ({
    title: localizedText(book.metadata?.title) ?? '',
    author: localizedText(book.metadata?.author),
    toc: serializeTOC(book.toc),
})

view.addEventListener('relocate', ({ detail }) => {
    send('relocate', {
        cfi: detail.cfi,
        fraction: detail.fraction ?? 0,
        chapterTitle: localizedText(detail.tocItem?.label),
    })
})

view.addEventListener('load', ({ detail: { doc, index } }) => {
    doc.addEventListener('selectionchange', () => {
        clearTimeout(selectionTimer)
        selectionTimer = setTimeout(() => {
            const selection = doc.getSelection()
            if (!selection || selection.isCollapsed || !selection.rangeCount) {
                send('selection-cleared')
                return
            }
            const range = selection.getRangeAt(0)
            send('selection', {
                quote: selection.toString(),
                cfi: view.getCFI(index, range),
            })
        }, 80)
    })
})

view.addEventListener('external-link', event => {
    event.preventDefault()
    send('external-link', { href: event.detail.href_ })
})

globalThis.leeefReader = {
    async open(bookURL, initialLocator) {
        if (currentBookURL) await view.close()
        currentBookURL = bookURL
        await view.open(bookURL)
        await view.init({
            lastLocation: initialLocator || null,
            showTextStart: !initialLocator,
        })
        return serializeMetadata(view.book)
    },
    next: () => view.next(),
    previous: () => view.prev(),
    goTo: locator => view.goTo(locator),
    close: async () => {
        await view.close()
        currentBookURL = null
    },
    setLayout: ({ flow = 'paginated', maxColumnCount = 1, margin = 24 }) => {
        view.setAttribute('flow', flow)
        view.setAttribute('max-column-count', String(maxColumnCount))
        view.setAttribute('margin', `${margin}px`)
    },
    probeLayout() {
        const contents = view.renderer.getContents()
        return {
            flow: view.getAttribute('flow'),
            maxColumnCount: Number(view.getAttribute('max-column-count')),
            margin: view.getAttribute('margin'),
            renderedSections: contents.length,
            textLength: contents.reduce(
                (length, { doc }) => length + (doc.body?.innerText?.length ?? 0),
                0,
            ),
            viewportWidth: window.innerWidth,
            viewportHeight: window.innerHeight,
        }
    },
    setTheme: ({ foreground, background, fontSize, lineHeight }) => {
        const style = document.documentElement.style
        if (foreground) style.setProperty('--reader-foreground', foreground)
        if (background) style.setProperty('--reader-background', background)
        if (fontSize) style.setProperty('--reader-font-size', `${fontSize}px`)
        if (lineHeight) style.setProperty('--reader-line-height', String(lineHeight))
    },
    async probeTextSelection() {
        const contents = view.renderer.getContents()
        for (const { doc, index } of contents) {
            const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
            let node
            while ((node = walker.nextNode())) {
                const start = node.data.search(/\S/)
                if (start < 0) continue
                const range = doc.createRange()
                range.setStart(node, start)
                range.setEnd(node, Math.min(node.length, start + 12))
                const selection = doc.getSelection()
                selection.removeAllRanges()
                selection.addRange(range)
                await new Promise(resolve => setTimeout(resolve, 120))
                return {
                    quote: selection.toString(),
                    cfi: view.getCFI(index, range),
                }
            }
        }
        throw new Error('No selectable text in the rendered section')
    },
}

send('ready')
