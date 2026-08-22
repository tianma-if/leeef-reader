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
    async captureSnapshotModel(viewport = {}) {
        const [{ doc }] = view.renderer.getContents()
        if (!doc) throw new Error('No rendered EPUB page to snapshot')
        const frameRect = doc.defaultView.frameElement.getBoundingClientRect()
        const viewportWidth = window.innerWidth || viewport.width || frameRect.width
        const viewportHeight = window.innerHeight || viewport.height || frameRect.height
        const parseColor = value => {
            if (value.startsWith('#')) {
                const hex = value.slice(1)
                const rgb = hex.length === 3
                    ? hex.split('').map(value => value + value).join('')
                    : hex.slice(0, 6)
                return (0xff000000 | Number.parseInt(rgb, 16)) >>> 0
            }
            const parts = value.match(/[\d.]+/g)?.map(Number) ?? []
            const [r = 41, g = 43, b = 41, a = 1] = parts
            return ((Math.round(a * 255) << 24) | (r << 16) | (g << 8) | b) >>> 0
        }
        const runs = []
        const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
            if (!node.data.trim()) continue
            const computed = doc.defaultView.getComputedStyle(node.parentElement)
            let run = null
            for (let offset = 0; offset < node.length; offset++) {
                const range = doc.createRange()
                range.setStart(node, offset)
                range.setEnd(node, offset + 1)
                const rect = range.getBoundingClientRect()
                const x = frameRect.left + rect.left
                const y = frameRect.top + rect.top
                const visible = rect.width > 0 && rect.height > 0 &&
                    x + rect.width > 0 && x < viewportWidth &&
                    y + rect.height > 0 && y < viewportHeight
                if (!visible) {
                    run = null
                    continue
                }
                const adjacent = run && Math.abs(run.y - y) < .75 &&
                    Math.abs(run.x + run.width - x) < 2
                if (!adjacent) {
                    run = {
                        text: '', x, y, width: 0, height: rect.height,
                        fontSize: parseFloat(computed.fontSize) || 18,
                        fontWeight: parseInt(computed.fontWeight) || 400,
                        fontStyle: computed.fontStyle,
                        letterSpacing: parseFloat(computed.letterSpacing) || 0,
                        color: parseColor(computed.color),
                    }
                    runs.push(run)
                }
                run.text += node.data[offset]
                run.width = x + rect.width - run.x
                run.height = Math.max(run.height, rect.height)
            }
        }
        const bodyStyle = doc.defaultView.getComputedStyle(doc.body)
        const htmlStyle = doc.defaultView.getComputedStyle(doc.documentElement)
        const transparent = value => value === 'transparent' ||
            value === 'rgba(0, 0, 0, 0)'
        const bodyBackground = bodyStyle.backgroundColor
        const background = transparent(bodyBackground)
            ? (transparent(htmlStyle.backgroundColor)
                ? getComputedStyle(document.documentElement).backgroundColor
                : htmlStyle.backgroundColor)
            : bodyBackground
        const images = await Promise.all(Array.from(doc.images, async image => {
            const rect = image.getBoundingClientRect()
            const x = frameRect.left + rect.left
            const y = frameRect.top + rect.top
            if (!rect.width || !rect.height || x + rect.width <= 0 ||
                x >= viewportWidth || y + rect.height <= 0 ||
                y >= viewportHeight) return null
            try {
                const canvas = document.createElement('canvas')
                canvas.width = Math.max(1, Math.round(rect.width))
                canvas.height = Math.max(1, Math.round(rect.height))
                canvas.getContext('2d').drawImage(image, 0, 0,
                    canvas.width, canvas.height)
                return { x, y, width: rect.width, height: rect.height,
                    data: canvas.toDataURL('image/png') }
            } catch (_) { return null }
        }))
        return {
            background: parseColor(background),
            foreground: parseColor(bodyStyle.color),
            images: images.filter(Boolean),
            runs,
            diagnostics: {
                frame: { x: frameRect.x, y: frameRect.y,
                    width: frameRect.width, height: frameRect.height },
                window: { width: window.innerWidth, height: window.innerHeight },
                document: { width: doc.documentElement.clientWidth,
                    height: doc.documentElement.clientHeight,
                    textLength: doc.body.innerText.length },
            },
        }
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
