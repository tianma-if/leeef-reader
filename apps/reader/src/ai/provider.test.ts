import { describe, expect, it } from 'vitest'
import { hasAiCredentials } from './provider'

describe('hasAiCredentials', () => {
  it('requires both endpoint and key', () => {
    expect(hasAiCredentials({})).toBe(false)
    expect(hasAiCredentials({ aiEndpoint: 'https://api.openai.com/v1' })).toBe(false)
    expect(hasAiCredentials({ aiKey: 'sk-test' })).toBe(false)
    expect(hasAiCredentials({ aiEndpoint: '  ', aiKey: 'sk-test' })).toBe(false)
    expect(
      hasAiCredentials({ aiEndpoint: 'https://api.openai.com/v1', aiKey: 'sk-test' }),
    ).toBe(true)
  })
})
