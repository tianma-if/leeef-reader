import { useId } from 'react'
import { Switch } from 'radix-ui'
import { cn } from '@/lib/utils'

type Choice<Value> = {
  value: Value
  label: string
  swatch?: { bg: string; fg: string }
}

export function SettingChoices<Value extends string | number>({
  label,
  options,
  value,
  onChange,
  disabled,
  layout = 'segments',
}: {
  label: string
  options: readonly Choice<Value>[]
  value: Value
  onChange: (value: Value) => void
  disabled?: boolean
  layout?: 'segments' | 'list'
}) {
  const name = useId()
  return (
    <fieldset disabled={disabled} className="min-w-0 disabled:opacity-60">
      <legend className="mb-2 text-sm font-medium">{label}</legend>
      <div className={cn(
        'grid',
        layout === 'segments'
          ? 'auto-cols-fr grid-flow-col gap-1 rounded-lg bg-muted p-1'
          : 'gap-2',
      )}>
        {options.map((option) => (
          <label key={option.value} className="relative min-w-0">
            <input
              className="peer sr-only"
              type="radio"
              name={name}
              value={option.value}
              checked={value === option.value}
              onChange={() => onChange(option.value)}
            />
            <span className={cn(
              'flex min-h-11 w-full cursor-pointer items-center gap-2 rounded-md text-sm text-muted-foreground transition-colors',
              'peer-checked:text-foreground peer-checked:font-medium peer-focus-visible:ring-2 peer-focus-visible:ring-ring peer-focus-visible:ring-offset-2 peer-focus-visible:ring-offset-background peer-disabled:cursor-default',
              layout === 'segments'
                ? 'justify-center border border-transparent px-1.5 py-1.5 text-center hover:text-foreground peer-checked:border-border peer-checked:bg-background peer-checked:shadow-xs'
                : 'border px-3 py-2 hover:bg-muted/60 peer-checked:border-primary peer-checked:bg-primary/5',
              option.swatch && 'flex-col',
            )}>
              {layout === 'list' && (
                <span aria-hidden="true" className="grid size-4 shrink-0 place-items-center rounded-full border border-current">
                  {value === option.value && <span className="size-2 rounded-full bg-primary" />}
                </span>
              )}
              {option.swatch && (
                <span aria-hidden="true" className="grid h-8 w-full place-items-center rounded-sm border border-black/10 font-serif font-medium"
                  style={{ color: option.swatch.fg, backgroundColor: option.swatch.bg }}>
                  字
                </span>
              )}
              <span className="min-w-0 break-words">{option.label}</span>
            </span>
          </label>
        ))}
      </div>
    </fieldset>
  )
}

export function SettingSwitch({
  label,
  checked,
  onChange,
}: {
  label: string
  checked: boolean
  onChange: (checked: boolean) => void
}) {
  const id = useId()
  return (
    <label htmlFor={id} className="flex min-h-12 cursor-pointer items-center justify-between gap-3 rounded-lg border px-3 py-2">
      <span className="text-sm font-medium">{label}</span>
      <Switch.Root
        id={id}
        checked={checked}
        onCheckedChange={onChange}
        className="inline-flex h-6 w-11 shrink-0 items-center rounded-full border-2 border-transparent bg-muted-foreground/40 transition-colors data-[state=checked]:bg-primary focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background focus-visible:outline-none"
      >
        <Switch.Thumb className="block size-5 rounded-full bg-white shadow-sm transition-transform data-[state=checked]:translate-x-5" />
      </Switch.Root>
    </label>
  )
}
