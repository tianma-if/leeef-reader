import '../vendor/foliate-js/view.js'

const view = document.querySelector('#reader')
const parent = window.parent

const send = (type, payload = {}) => {
  parent.postMessage({ source: 'leeef-reader', type, ...payload }, '*')
}

const localizedText = (value) => {
  if (typeof value === 'string') return value
  if (Array.isArray(value)) return localizedText(value[0])
  if (value && typeof value === 'object') {
    return (
      localizedText(value[document.documentElement.lang]) ??
      localizedText(Object.values(value)[0])
    )
  }
  return null
}

const applyLayout = ({
  flow = 'paginated',
  maxColumnCount = 1,
  margin = 24,
  animated = false,
  noSwipe = false,
} = {}) => {
  view.setAttribute('flow', flow)
  view.setAttribute('max-column-count', String(maxColumnCount))
  view.setAttribute('margin', `${margin}px`)
  view.setAttribute('max-block-size', '10000px')
  if (animated) view.setAttribute('animated', '')
  else view.removeAttribute('animated')
  if (noSwipe) view.setAttribute('no-swipe', '')
  else view.removeAttribute('no-swipe')
}

view.addEventListener('relocate', ({ detail }) => {
  send('relocate', {
    cfi: detail.cfi,
    fraction: detail.fraction ?? 0,
    atStart: view.renderer.atStart,
    atEnd: view.renderer.atEnd,
    chapterTitle: localizedText(detail.tocItem?.label),
  })
})

view.addEventListener('tap', ({ detail }) => {
  const x = Number(detail?.x)
  if (!Number.isFinite(x)) return
  send('tap', { x, width: window.innerWidth })
})

const openBook = async ({ name, bytes, locator, layout }) => {
  const file = new File([bytes], name)
  applyLayout(layout)
  await view.open(file)
  await view.init({
    lastLocation: locator || null,
    showTextStart: !locator,
  })
  send('opened', {
    title: localizedText(view.book?.metadata?.title) ?? name,
  })
}

window.addEventListener('message', async (event) => {
  const data = event.data
  if (!data || data.source !== 'leeef-shell') return
  try {
    switch (data.type) {
      case 'open':
        await openBook(data)
        break
      case 'next':
        await view.next()
        break
      case 'prev':
        await view.prev()
        break
      case 'layout':
        applyLayout(data.layout)
        break
      default:
        break
    }
  } catch (error) {
    send('error', { message: String(error) })
  }
})

send('ready')
