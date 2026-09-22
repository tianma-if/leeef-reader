import { expect, it } from 'vitest'
import { loadSelectionHistory, saveSelectionHistory } from './selectionHistory'

it('round-trips visible dialogue and excludes reasoning from persistence', () => {
  const values = new Map<string, string>()
  const storage = { getItem: (key: string) => values.get(key) ?? null, setItem: (key: string, value: string) => { values.set(key, value) } }
  saveSelectionHistory(storage, 'selection', [{ id: 'answer', role: 'assistant', parts: [
    { type: 'reasoning', text: 'not user-facing' }, { type: 'text', text: 'Answer' },
  ] }])
  expect(loadSelectionHistory(storage, 'selection')).toEqual([{ id: 'answer', role: 'assistant', parts: [{ type: 'text', text: 'Answer' }] }])
  values.set('selection', '{broken')
  expect(loadSelectionHistory(storage, 'selection')).toEqual([])
})
