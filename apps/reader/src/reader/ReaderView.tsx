import { useEffect, useRef, useState } from 'react'
import { CapturedPageTurn } from './capturedTurn'
import { isMobileShell } from './nativeCapture'

type Props = {
  fileName: string
  bytes: Uint8Array
  onClose: () => void
}

type IframeMessage = {
  source?: string
  type?: string
  title?: string
  x?: number
  width?: number
  fraction?: number
  atStart?: boolean
  atEnd?: boolean
  message?: string
}

export function ReaderView({ fileName, bytes, onClose }: Props) {
  const hostRef = useRef<HTMLDivElement>(null)
  const iframeRef = useRef<HTMLIFrameElement>(null)
  const [title, setTitle] = useState(fileName)
  const [progress, setProgress] = useState(0)
  const [error, setError] = useState<string | null>(null)
  const openedRef = useRef(false)
  const dragRef = useRef<{
    startX: number
    width: number
    forward: boolean
    session: Awaited<ReturnType<CapturedPageTurn['beginDrag']>>
  } | null>(null)

  const post = (payload: Record<string, unknown>) => {
    iframeRef.current?.contentWindow?.postMessage(
      { source: 'leeef-shell', ...payload },
      '*',
    )
  }

  const openBook = () => {
    if (openedRef.current) return
    openedRef.current = true
    post({
      type: 'open',
      name: fileName,
      bytes: bytes.slice().buffer,
      layout: {
        flow: 'paginated',
        animated: !mobile,
        noSwipe: mobile,
      },
    })
  }

  const mobile = isMobileShell()

  useEffect(() => {
    const onMessage = (event: MessageEvent<IframeMessage>) => {
      if (event.data?.source !== 'leeef-reader') return
      switch (event.data.type) {
        case 'ready':
          openBook()
          break
        case 'opened':
          if (event.data.title) setTitle(event.data.title)
          break
        case 'relocate':
          setProgress(Math.round((event.data.fraction ?? 0) * 1000) / 10)
          break
        case 'tap': {
          const x = event.data.x ?? 0
          const width = event.data.width ?? 1
          if (x / width < 0.28) void turn(false)
          else if (x / width > 0.72) void turn(true)
          break
        }
        case 'error':
          setError(event.data.message ?? '阅读器错误')
          break
        default:
          break
      }
    }
    window.addEventListener('message', onMessage)
    return () => window.removeEventListener('message', onMessage)
  }, [bytes, fileName, mobile])

  const controller = () =>
    new CapturedPageTurn({
      getHostElement: () => hostRef.current,
      getContentRect: () => iframeRef.current?.getBoundingClientRect() ?? null,
      navigate: async (forward) => {
        post({ type: forward ? 'next' : 'prev' })
        await new Promise((resolve) => setTimeout(resolve, 16))
      },
    })

  const turn = async (forward: boolean) => {
    if (!mobile) {
      post({ type: forward ? 'next' : 'prev' })
      return
    }
    try {
      await controller().turn(forward)
    } catch {
      post({ type: forward ? 'next' : 'prev' })
    }
  }

  const onPointerDown = async (event: React.PointerEvent<HTMLDivElement>) => {
    if (!mobile || !hostRef.current) return
    const rect = hostRef.current.getBoundingClientRect()
    const x = event.clientX - rect.left
    const edge = rect.width * 0.4
    if (x > edge && x < rect.width - edge) return
    const forward = x >= rect.width - edge
    event.currentTarget.setPointerCapture(event.pointerId)
    try {
      const session = await controller().beginDrag(forward)
      if (!session) return
      dragRef.current = {
        startX: event.clientX,
        width: rect.width,
        forward,
        session,
      }
    } catch {
      post({ type: forward ? 'next' : 'prev' })
    }
  }

  const onPointerMove = (event: React.PointerEvent<HTMLDivElement>) => {
    const drag = dragRef.current
    if (!drag?.session) return
    const delta = event.clientX - drag.startX
    const signed = drag.forward ? -delta : delta
    const progress = Math.min(1, Math.max(0, signed / drag.width))
    drag.session.overlayEl.dataset.progress = String(progress)
    drag.session.setProgress(progress)
  }

  const onPointerUp = async () => {
    const drag = dragRef.current
    dragRef.current = null
    if (!drag?.session) return
    const progress = Number(drag.session.overlayEl.dataset.progress ?? '0')
    await drag.session.finish(progress > 0.28)
  }

  return (
    <div className="reader-shell" ref={hostRef}>
      <header className="reader-chrome">
        <button type="button" onClick={onClose}>
          书库
        </button>
        <strong>{title}</strong>
        <span>{progress.toFixed(1)}%</span>
      </header>
      <div className="reader-stage">
        <iframe
          ref={iframeRef}
          className="reader-frame"
          title="reader"
          src="/reader/index.html"
          onLoad={() => {
            if (!openedRef.current) openBook()
          }}
        />
        {mobile ? (
          <div
            className="reader-gesture"
            onPointerDown={(event) => void onPointerDown(event)}
            onPointerMove={onPointerMove}
            onPointerUp={() => void onPointerUp()}
            onPointerCancel={() => void onPointerUp()}
          />
        ) : null}
      </div>
      {error ? <p className="reader-error">{error}</p> : null}
    </div>
  )
}
