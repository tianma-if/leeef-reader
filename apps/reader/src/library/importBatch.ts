export type ImportFailure<T> = { item: T; error: string }

export async function importBatch<T>(
  items: T[],
  importOne: (item: T) => Promise<unknown>,
  onProgress?: (completed: number) => void,
) {
  const failures: ImportFailure<T>[] = []
  let succeeded = 0
  for (const [index, item] of items.entries()) {
    try {
      await importOne(item)
      succeeded += 1
    } catch (cause) {
      failures.push({ item, error: cause instanceof Error ? cause.message : String(cause) })
    }
    onProgress?.(index + 1)
  }
  return { succeeded, failures }
}
