/** Normalize platform line endings without collapsing paragraph structure. */
export const normalizeSelectedText = (value: string) =>
  value.replace(/\r\n?/g, '\n').trim()
