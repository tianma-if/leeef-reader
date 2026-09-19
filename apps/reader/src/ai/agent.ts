import {
  DirectChatTransport,
  InferAgentUIMessage,
  isStepCount,
  ToolLoopAgent,
} from 'ai'
import type { Settings } from '../api'
import { defaultLibrary, type LeeefLibrary } from './library'
import { createLeeefModel } from './provider'
import { createLeeefTools, WRITE_TOOL_NAMES } from './tools'

export const LEEEF_INSTRUCTIONS = `你是 Leeef Reader 的阅读助手。基于书库、书摘、书签和阅读进度回答，明确区分原文事实与推断，不编造不存在的引用。
需要查书库、书架、标签、书摘、书签或进度时，使用工具，不要猜测书籍 id。
写操作会先向用户确认；未获确认时不要声称已经改成功。
用用户的语言回答。`

export function createLeeefAgent(settings: Settings, library: LeeefLibrary = defaultLibrary) {
  const tools = createLeeefTools(library)
  return new ToolLoopAgent({
    model: createLeeefModel(settings),
    instructions: LEEEF_INSTRUCTIONS,
    tools,
    stopWhen: isStepCount(8),
    toolApproval: ({ toolCall }) => {
      if (toolCall.dynamic) return undefined
      return WRITE_TOOL_NAMES.has(toolCall.toolName) ? 'user-approval' : undefined
    },
  })
}

export type LeeefAgent = ReturnType<typeof createLeeefAgent>
export type LeeefUIMessage = InferAgentUIMessage<LeeefAgent>

export function createLeeefTransport(settings: Settings, library: LeeefLibrary = defaultLibrary) {
  return new DirectChatTransport({
    agent: createLeeefAgent(settings, library),
    onError: (error) => (error instanceof Error ? error.message : String(error)),
  })
}
