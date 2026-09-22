import { describe, expect, it } from 'vitest'
import { countReadingDays, readingDay } from './readingDays'
import type { Session } from '../api'

describe('reading days', () => {
  it('groups seconds and ISO dates by the local calendar day', () => {
    const morning = new Date(2026, 8, 22, 8)
    const evening = new Date(2026, 8, 22, 20)
    const nextDay = new Date(2026, 8, 23, 8)
    const sessions = [morning, evening, nextDay].map((date, index) => ({
      id: String(index), bookId: 'book', durationSeconds: 10,
      startedAt: index === 1 ? date.toISOString() : String(date.getTime() / 1000),
      endedAt: date.toISOString(),
    }))
    expect(countReadingDays(sessions)).toBe(2)
    expect(readingDay(morning.toISOString())).toBe('2026-9-22')
  })

  it('ignores invalid dates and empty sessions', () => {
    const sessions = [
      { startedAt: 'invalid', durationSeconds: 10 },
      { startedAt: '2026-09-22T12:00:00Z', durationSeconds: 0 },
    ] as Session[]
    expect(countReadingDays(sessions)).toBe(0)
  })
})
