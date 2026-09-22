import { expect, it, vi } from 'vitest'
import { createReadingTimer } from './readingTimer'

it('excludes loading and background time, and checkpoints without double counting', async () => {
  let time = 0
  const save = vi.fn(async () => undefined)
  const timer = createReadingTimer(save, () => time)
  time = 10_000
  timer.setActive(true)
  time = 40_500
  await timer.flush()
  time = 45_000
  timer.setActive(false)
  await timer.flush()
  time = 200_000
  await timer.flush()
  timer.setActive(true)
  time = 205_000
  timer.setActive(false)
  await timer.flush()
  await timer.flush()
  expect(save.mock.calls).toEqual([[30], [5], [5]])
})

it('retains unsaved duration for a subsequent retry', async () => {
  let time = 0
  const save = vi.fn<(seconds: number) => Promise<void>>()
    .mockRejectedValueOnce(new Error('busy')).mockResolvedValue(undefined)
  const timer = createReadingTimer(save, () => time)
  timer.setActive(true)
  time = 5000
  await expect(timer.flush()).rejects.toThrow('busy')
  time = 10_000
  timer.setActive(false)
  await timer.flush()
  expect(save.mock.calls).toEqual([[5], [10]])
})

it('includes a failed pending save in the queued final checkpoint', async () => {
  let time = 0
  let fail: ((error: Error) => void) | undefined
  const save = vi.fn<(seconds: number) => Promise<void>>()
    .mockImplementationOnce(() => new Promise((_, reject) => { fail = reject }))
    .mockResolvedValue(undefined)
  const timer = createReadingTimer(save, () => time)
  timer.setActive(true)
  time = 5000
  const first = timer.flush()
  const rejected = expect(first).rejects.toThrow('busy')
  await Promise.resolve()
  time = 10000
  timer.setActive(false)
  const final = timer.flush()
  fail!(new Error('busy'))
  await rejected
  await final
  expect(save.mock.calls).toEqual([[5], [10]])
})
