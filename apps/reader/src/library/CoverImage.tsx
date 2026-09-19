import { useEffect, useState } from 'react'
import { api, type Book } from '../api'

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
    return (
      <div className="grid size-full place-items-center bg-linear-to-br from-[#3d4a3c] to-[#1f2a1e] text-2xl text-[#f4efe6]">
        {book.title.slice(0, 1)}
      </div>
    )
  }

  return <img src={url} alt="" className="size-full object-cover" />
}
