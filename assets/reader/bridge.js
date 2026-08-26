import '../foliate-js/view.js'

const view = document.querySelector('#reader')
let currentBookURL
let selectionTimer
let ttsHighlight
let allowBookJavaScript = false
const originalChineseText = new WeakMap()

const enforceBookScriptPolicy = doc => {
    if (allowBookJavaScript) return
    doc.querySelectorAll('script').forEach(node => node.remove())
    new MutationObserver(records => {
        for (const record of records) for (const node of record.addedNodes) {
            if (node.nodeType !== Node.ELEMENT_NODE) continue
            if (node.matches?.('script')) node.remove()
            node.querySelectorAll?.('script').forEach(script => script.remove())
        }
    }).observe(doc.documentElement, { childList: true, subtree: true })
}

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
    enforceBookScriptPolicy(doc)
    doc.addEventListener('click', async event => {
        const image = event.target?.closest?.('img,svg image')
        if (image) {
            event.preventDefault()
            event.stopImmediatePropagation()
            let source = image.currentSrc || image.src || image.getAttribute('href') || ''
            try {
                const blob = await fetch(source).then(response => response.blob())
                source = await new Promise((resolve, reject) => {
                    const reader = new FileReader()
                    reader.onload = () => resolve(reader.result)
                    reader.onerror = reject
                    reader.readAsDataURL(blob)
                })
            } catch (_) { /* Fall back to the resolved source URL. */ }
            send('image', {
                source,
                description: image.alt || image.getAttribute('aria-label') || '',
            })
            return
        }
        const anchor = event.target?.closest?.('a[href^="#"]')
        if (!anchor) return
        const id = decodeURIComponent(anchor.getAttribute('href').slice(1))
        const target = doc.getElementById(id)
        if (!target) return
        const semantics = `${target.getAttribute('epub:type') || ''} ${target.getAttribute('role') || ''}`
        if (!/(footnote|doc-note|note)/i.test(semantics) && target.innerText.length > 800) return
        event.preventDefault()
        event.stopImmediatePropagation()
        send('footnote', {
            title: anchor.innerText?.trim() || '脚注',
            text: target.innerText?.trim() || '',
        })
    }, true)
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
    send('external-link', { href: event.detail.a?.href || event.detail.href_ })
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
    historyBack: () => view.history.back(),
    historyForward: () => view.history.forward(),
    historyState: () => ({
        canGoBack: view.history.canGoBack,
        canGoForward: view.history.canGoForward,
    }),
    goTo: locator => view.goTo(locator),
    close: async () => {
        await view.close()
        currentBookURL = null
    },
    setLayout: ({ flow = 'paginated', maxColumnCount = 1, margin = 24,
        pageTurnEffect = 'slide' }) => {
        view.setAttribute('flow', flow)
        view.setAttribute('max-column-count', String(maxColumnCount))
        view.setAttribute('margin', `${margin}px`)
        if (pageTurnEffect === 'slide') view.setAttribute('animated', '')
        else view.removeAttribute('animated')
    },
    setBookJavaScriptEnabled: enabled => {
        allowBookJavaScript = enabled === true
        if (!allowBookJavaScript) {
            for (const { doc } of view.renderer.getContents()) enforceBookScriptPolicy(doc)
        }
    },
    probeLayout() {
        const contents = view.renderer.getContents()
        return {
            flow: view.getAttribute('flow'),
            maxColumnCount: Number(view.getAttribute('max-column-count')),
            margin: view.getAttribute('margin'),
            animated: view.hasAttribute('animated'),
            renderedSections: contents.length,
            textLength: contents.reduce(
                (length, { doc }) => length + (doc.body?.innerText?.length ?? 0),
                0,
            ),
            viewportWidth: window.innerWidth,
            viewportHeight: window.innerHeight,
        }
    },
    setTheme: ({ foreground, background, fontSize, lineHeight, fontFamily,
        fontWeight, headingScale, letterSpacing, paragraphSpacing, textIndent,
        textAlign, writingMode, preserveBookStyles, eInkMode, codeHighlight,
        backgroundImage, backgroundOpacity, backgroundBlur, backgroundFit,
        importedFontName, importedFontData, customCSS }) => {
        const style = document.documentElement.style
        if (foreground) style.setProperty('--reader-foreground', foreground)
        if (background) style.setProperty('--reader-background', background)
        if (fontSize) style.setProperty('--reader-font-size', `${fontSize}px`)
        if (lineHeight) style.setProperty('--reader-line-height', String(lineHeight))
        const fontFace = importedFontData && importedFontName ? `
            @font-face {
                font-family: 'LeeefImportedFont';
                src: url('${importedFontData}');
                font-display: swap;
            }` : ''
        const typography = preserveBookStyles ? '' : `
            body, body *:not(svg):not(svg *) {
                font-family: ${fontFamily || 'serif'} !important;
                font-size: ${fontSize || 18}px !important;
                font-weight: ${fontWeight || 400} !important;
                line-height: ${lineHeight || 1.65} !important;
                letter-spacing: ${letterSpacing || 0}px !important;
                text-align: ${textAlign || 'start'} !important;
            }`
        const codeTheme = codeHighlight ? `
            pre, code { font-family: monospace !important; }
            pre { padding: .8em; border-radius: .45em; overflow: auto;
                color: ${eInkMode ? '#000' : '#d8dee9'} !important;
                background: ${eInkMode ? '#fff' : '#20242b'} !important; }
            .keyword, .hljs-keyword { color: ${eInkMode ? '#000' : '#c678dd'} !important; font-weight: 700; }
            .string, .hljs-string { color: ${eInkMode ? '#333' : '#98c379'} !important; }
            .comment, .hljs-comment { color: ${eInkMode ? '#666' : '#7f848e'} !important; font-style: italic; }
            .number, .hljs-number { color: ${eInkMode ? '#222' : '#d19a66'} !important; }` : ''
        const imageLayer = backgroundImage ? `
            html { background: ${background || 'transparent'} !important; }
            body { background: transparent !important; isolation: isolate; }
            body::before {
                content: ''; position: fixed; inset: -${backgroundBlur || 0}px;
                z-index: -1; pointer-events: none;
                opacity: ${backgroundOpacity ?? .18};
                filter: blur(${backgroundBlur || 0}px);
                background-image: url('${backgroundImage}');
                background-position: center;
                background-repeat: no-repeat;
                background-size: ${backgroundFit || 'cover'};
            }` : ''
        const css = `${fontFace}
            :root { color-scheme: light dark !important; }
            html, body {
                color: ${foreground || 'inherit'} !important;
                background: ${backgroundImage ? 'transparent' : (background || 'transparent')} !important;
                font-family: ${fontFamily || 'serif'} !important;
                font-size: ${fontSize || 18}px !important;
                font-weight: ${fontWeight || 400} !important;
                line-height: ${lineHeight || 1.65} !important;
                letter-spacing: ${letterSpacing || 0}px !important;
                text-align: ${textAlign || 'start'} !important;
                writing-mode: ${writingMode || 'horizontal-tb'} !important;
            }
            body { ${eInkMode ? 'filter: grayscale(1) contrast(1.12);' : ''} }
            p { margin-block: ${paragraphSpacing ?? 0.65}em !important;
                text-indent: ${textIndent || 0}em !important; }
            h1 { font-size: ${(fontSize || 18) * (headingScale || 1.25) * 1.35}px !important; }
            h2 { font-size: ${(fontSize || 18) * (headingScale || 1.25) * 1.15}px !important; }
            h3, h4, h5, h6 { font-size: ${(fontSize || 18) * (headingScale || 1.25)}px !important; }
            ${typography}
            ${imageLayer}
            ${codeTheme}
            ${customCSS || ''}`
        view.renderer.setStyles?.(css)
    },
    async search(query) {
        const results = []
        for await (const result of view.search({ query })) {
            if (!result || typeof result !== 'object' || !result.subitems) continue
            for (const item of result.subitems) results.push({
                label: localizedText(result.label) ?? '',
                cfi: item.cfi,
                excerpt: item.excerpt
                    ? `${item.excerpt.pre}${item.excerpt.match}${item.excerpt.post}`
                    : '',
            })
        }
        return results
    },
    clearSearch: () => view.clearSearch(),
    currentText: () => view.renderer.getContents()
        .map(({ doc }) => doc.body?.innerText ?? '')
        .filter(Boolean)
        .join('\n'),
    bookText: async ({ maxCharacters = 2000000 } = {}) => {
        const output = []
        let length = 0
        for (const section of view.book?.sections ?? []) {
            if (!section.createDocument || length >= maxCharacters) continue
            const doc = await section.createDocument()
            const text = (doc.body?.innerText ?? doc.documentElement?.textContent ?? '')
                .replace(/\s+\n/g, '\n').trim()
            if (!text) continue
            const remaining = maxCharacters - length
            output.push(text.slice(0, remaining))
            length += Math.min(text.length, remaining)
        }
        return output.join('\n\n')
    },
    visibleTextNodes() {
        const nodes = []
        for (const { doc } of view.renderer.getContents()) {
            const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
            for (let node = walker.nextNode(); node; node = walker.nextNode()) {
                if (!node.data.trim()) continue
                if (!originalChineseText.has(node)) originalChineseText.set(node, node.data)
                nodes.push(originalChineseText.get(node))
            }
        }
        return nodes
    },
    applyVisibleTextNodes(texts) {
        let index = 0
        for (const { doc } of view.renderer.getContents()) {
            const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
            for (let node = walker.nextNode(); node; node = walker.nextNode()) {
                if (!node.data.trim()) continue
                if (!originalChineseText.has(node)) originalChineseText.set(node, node.data)
                node.data = texts?.[index] ?? originalChineseText.get(node)
                index++
            }
        }
        return index
    },
    highlightTtsSentence(sentence) {
        ttsHighlight?.replaceWith(...ttsHighlight.childNodes)
        ttsHighlight = null
        if (!sentence) return false
        for (const { doc } of view.renderer.getContents()) {
            const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
            for (let node = walker.nextNode(); node; node = walker.nextNode()) {
                const index = node.data.indexOf(sentence)
                if (index < 0) continue
                const range = doc.createRange()
                range.setStart(node, index)
                range.setEnd(node, index + sentence.length)
                const mark = doc.createElement('mark')
                mark.dataset.leeefTts = 'true'
                mark.style.cssText = 'background:#ffd54f;color:inherit;border-radius:.15em;'
                range.surroundContents(mark)
                mark.scrollIntoView({ block: 'center', behavior: 'smooth' })
                ttsHighlight = mark
                return true
            }
        }
        return false
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
