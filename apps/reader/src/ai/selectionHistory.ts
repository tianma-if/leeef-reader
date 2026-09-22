import type { SelectionMessage } from './selectionAgent'

export const selectionHistoryKey = (bookId: string, locator: string) =>
  `leeef:selection-chat:v1:${bookId}:${locator}`

export function loadSelectionHistory(storage: Pick<Storage, 'getItem'>, key: string): SelectionMessage[] {
  try {
    const value: unknown = JSON.parse(storage.getItem(key) ?? '[]')
    if (!Array.isArray(value)) return []
    return value.filter((message) => message && typeof message.id === 'string'
      && (message.role === 'user' || message.role === 'assistant') && Array.isArray(message.parts))
      .map((message) => ({ id: message.id, role: message.role,
        parts: message.parts.filter((part: { type?: string; text?: unknown }) => part.type === 'text' && typeof part.text === 'string') }))
      .filter((message) => message.parts.length > 0)
  } catch { return [] }
}

export function saveSelectionHistory(storage: Pick<Storage, 'setItem'>, key: string, messages: SelectionMessage[]) {
  storage.setItem(key, JSON.stringify(messages.map((message) => ({ ...message,
    parts: message.parts.filter((part) => part.type === 'text'),
  }))))
}
