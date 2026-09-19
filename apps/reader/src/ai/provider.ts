import { createOpenAICompatible } from '@ai-sdk/openai-compatible'
import type { Settings } from '../api'

export const DEFAULT_AI_MODEL = 'gpt-4o-mini'

export function hasAiCredentials(settings: Settings): boolean {
  return Boolean(settings.aiEndpoint?.trim() && settings.aiKey?.trim())
}

export function createLeeefModel(settings: Settings) {
  const baseURL = settings.aiEndpoint?.trim().replace(/\/+$/, '')
  const apiKey = settings.aiKey?.trim()
  const modelId = settings.aiModel?.trim() || DEFAULT_AI_MODEL
  if (!baseURL || !apiKey) {
    throw new Error('未配置 AI Endpoint 或 API Key')
  }
  const provider = createOpenAICompatible({
    name: 'leeef',
    baseURL,
    apiKey,
  })
  return provider.chatModel(modelId)
}
