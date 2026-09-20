import { resolveFont } from './fonts'

const buffers = new Map<string, Promise<ArrayBuffer>>()
const mounted = new WeakMap<Document, Set<string>>()

const fontUrl = (file: string) => new URL(`/fonts/${file}`, window.location.href).href

const loadBuffer = (file: string) => {
  const hit = buffers.get(file)
  if (hit) return hit
  const pending = fetch(fontUrl(file)).then(async (response) => {
    if (!response.ok) throw new Error(`无法加载字体 ${file}`)
    return response.arrayBuffer()
  })
  buffers.set(file, pending)
  return pending
}

export const mountReadingFont = async (doc: Document, fontFamily?: string) => {
  const font = resolveFont(fontFamily)
  if (!font.files.length || !font.family) return
  const win = doc.defaultView
  if (!win?.FontFace) return
  let ids = mounted.get(doc)
  if (!ids) {
    ids = new Set()
    mounted.set(doc, ids)
  }
  if (ids.has(font.id)) {
    await doc.fonts.ready.catch(() => undefined)
    return
  }
  for (const file of font.files) {
    const buffer = await loadBuffer(file)
    const face = new win.FontFace(font.family, buffer, {
      style: 'normal',
      weight: '400',
      display: 'swap',
    })
    await face.load()
    doc.fonts.add(face)
  }
  ids.add(font.id)
  await doc.fonts.ready.catch(() => undefined)
}

export const mountReadingFontOnView = async (
  view: FoliateViewElement | null | undefined,
  fontFamily?: string,
) => {
  if (!view) return
  const docs = (view.renderer?.getContents?.() ?? [])
    .map((item) => item.doc)
    .filter((doc): doc is Document => Boolean(doc))
  await Promise.all(docs.map((doc) => mountReadingFont(doc, fontFamily).catch(() => undefined)))
}
