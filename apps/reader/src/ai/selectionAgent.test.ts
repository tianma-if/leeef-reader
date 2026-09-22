import { expect, it } from 'vitest'
import { conversationNote, selectionInstructions } from './selectionAgent'

it('supplies only the selected source and limits citation claims', () => {
  const prompt = selectionInstructions({ bookTitle: 'Book', chapter: 'Chapter', locator: 'private-locator', quote: 'Quoted text' })
  expect(prompt).toContain('不是整本书')
  expect(prompt).toContain('[原文](#source)')
  expect(prompt).toContain('Quoted text')
  expect(prompt).not.toContain('private-locator')
})

it('saves visible questions and answers without hidden reasoning', () => {
  const note = conversationNote([
    { id: 'u', role: 'user', parts: [{ type: 'text', text: 'Explain' }] },
    { id: 'a', role: 'assistant', parts: [{ type: 'reasoning', text: 'hidden' }, { type: 'text', text: 'Answer' }] },
  ])
  expect(note).toContain('提问：Explain')
  expect(note).toContain('AI：Answer')
  expect(note).not.toContain('hidden')
})
