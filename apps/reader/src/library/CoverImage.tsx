import { useEffect, useState } from 'react'
import { BookOpen } from 'lucide-react'
import { api, type Book } from '../api'

const COVER_PALETTES = [
  'from-[#2c3e35] to-[#18241e]', // 墨绿
  'from-[#343e48] to-[#1c232a]', // 黛蓝
  'from-[#483434] to-[#2a1c1c]', // 赭红
  'from-[#2e3848] to-[#19202a]', // 藏青
  'from-[#42382b] to-[#261f16]', // 琥珀褐
]

export function CoverImage({ book }: { book: Book }) {
  const [url, setUrl] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    let objectUrl: string | null = null
    void api
      .bookCover(book.id)
      .then((bytes) => {
        if (cancelled || bytes.byteLength === 0) return
        objectUrl = URL.createObjectURL(new Blob([bytes]))
        if (cancelled) {
          URL.revokeObjectURL(objectUrl)
          objectUrl = null
          return
        }
        setUrl(objectUrl)
      })
      .catch(() => undefined)
    return () => {
      cancelled = true
      if (objectUrl) URL.revokeObjectURL(objectUrl)
    }
  }, [book.id])

  if (!url) {
    const hash = Math.abs(
      (book.title + (book.author ?? '')).split('').reduce((acc, c) => acc + c.charCodeAt(0), 0),
    )
    const gradient = COVER_PALETTES[hash % COVER_PALETTES.length]

    return (
      <div
        className={`relative flex size-full flex-col justify-between overflow-hidden bg-gradient-to-br ${gradient} p-2.5 text-[#f4efe6] shadow-inner select-none`}
      >
        {/* Book spine simulation */}
        <div className="absolute inset-y-0 left-0 w-2.5 bg-gradient-to-r from-black/40 to-transparent pointer-events-none" />
        <div className="absolute inset-y-0 left-2.5 w-px bg-white/10 pointer-events-none" />

        {/* Top decoration */}
        <div className="flex items-center justify-between text-white/40">
          <BookOpen className="size-3" />
          <span className="text-[9px] uppercase tracking-wider font-mono opacity-60">
            {book.mediaType.includes('pdf') ? 'PDF' : 'EPUB'}
          </span>
        </div>

        {/* Center Title */}
        <div className="my-auto py-1 pl-1">
          <p className="font-serif text-xs font-semibold leading-snug line-clamp-3 text-white/95 drop-shadow-xs">
            {book.title}
          </p>
        </div>

        {/* Bottom Author */}
        <div className="border-t border-white/15 pt-1.5 pl-1">
          <p className="truncate text-[10px] text-white/60">
            {book.author || '未知作者'}
          </p>
        </div>
      </div>
    )
  }

  return <img src={url} alt="" className="size-full object-cover" />
}
