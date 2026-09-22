import type { Session } from '../api'

export function readingDay(value: string): string | null {
  const date = /^\d+$/.test(value) ? new Date(Number(value) * 1000) : new Date(value)
  if (!Number.isFinite(date.getTime())) return null
  return `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`
}

export function countReadingDays(sessions: Session[]): number {
  return new Set(sessions
    .filter((session) => session.durationSeconds > 0)
    .map((session) => readingDay(session.startedAt))
    .filter((day) => day !== null)).size
}
