import { expect, it, vi } from 'vitest'
import { TurnQueue } from './turnQueue'

it('finishes the current turn and keeps only the most recent follow-up intent', async () => {
  let finish!: () => void
  const events: string[] = []
  const queue = new TurnQueue(vi.fn())
  queue.run(async () => {
    events.push('next:start')
    await new Promise<void>((resolve) => { finish = resolve })
    events.push('next:end')
  })
  queue.run(async () => { events.push('next:stale') })
  queue.run(async () => { events.push('prev') })
  expect(events).toEqual(['next:start'])
  finish()
  await vi.waitFor(() => expect(queue.busy).toBe(false))
  expect(events).toEqual(['next:start', 'next:end', 'prev'])
})

it('drops queued navigation when leaving the reader', async () => {
  let finish!: () => void
  const queue = new TurnQueue(vi.fn())
  queue.run(() => new Promise<void>((resolve) => { finish = resolve }))
  const stale = vi.fn()
  queue.run(stale)
  queue.clear()
  finish()
  await vi.waitFor(() => expect(queue.busy).toBe(false))
  expect(stale).not.toHaveBeenCalled()
})

it('reports failure, drops stale input and accepts a fresh turn', async () => {
  const onError = vi.fn()
  const queue = new TurnQueue(onError)
  queue.run(async () => { throw new Error('navigation failed') })
  const stale = vi.fn()
  queue.run(stale)
  await vi.waitFor(() => expect(queue.busy).toBe(false))
  expect(onError).toHaveBeenCalledOnce()
  expect(stale).not.toHaveBeenCalled()
  const next = vi.fn().mockResolvedValue(undefined)
  queue.run(next)
  await vi.waitFor(() => expect(queue.busy).toBe(false))
  expect(next).toHaveBeenCalledOnce()
})
