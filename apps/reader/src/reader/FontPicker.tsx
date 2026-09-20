import { useEffect } from 'react'
import { cn } from '@/lib/utils'
import { READING_FONTS, resolveFont } from './fonts'
import { mountReadingFont } from './fontLoader'

type Props = {
  value?: string
  onChange: (fontFamily: string) => void
}

export function FontPicker({ value, onChange }: Props) {
  const current = resolveFont(value).id

  useEffect(() => {
    let cancelled = false
    const bundled = READING_FONTS.filter((font) => font.files.length)
    const rest = bundled.filter((font) => font.id !== current)
    const load = async () => {
      await mountReadingFont(document, current).catch(() => undefined)
      for (const font of rest) {
        if (cancelled) return
        await mountReadingFont(document, font.id).catch(() => undefined)
      }
    }
    void load()
    return () => {
      cancelled = true
    }
  }, [current])

  return (
    <div className="grid grid-cols-2 gap-2">
      {READING_FONTS.map((font) => {
        const selected = current === font.id
        return (
          <button
            key={font.id}
            type="button"
            className={cn(
              'rounded-lg border px-2.5 py-2 text-left transition-colors',
              selected
                ? 'border-primary bg-primary/10'
                : 'border-border bg-background/70 hover:bg-muted',
            )}
            style={font.family ? { fontFamily: `"${font.family}", ${font.stack}` } : undefined}
            onClick={() => onChange(font.id)}
          >
            <span className="block text-sm leading-tight">{font.label}</span>
            <span className="text-muted-foreground mt-0.5 block truncate text-xs">
              {font.sample}
            </span>
          </button>
        )
      })}
    </div>
  )
}
