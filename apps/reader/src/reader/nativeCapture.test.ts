import { beforeEach, describe, expect, it, vi } from 'vitest'

const { invoke } = vi.hoisted(() => ({ invoke: vi.fn() }))

vi.mock('@tauri-apps/api/core', () => ({ invoke }))

import { setCoverProgress } from './nativeCapture'

describe('setCoverProgress', () => {
  beforeEach(() => invoke.mockReset())

  it('sends an integer animation duration to the native u64 command', async () => {
    await setCoverProgress(0.4, true, 102.9365)

    expect(invoke).toHaveBeenCalledWith('plugin:native-bridge|set_cover_progress', {
      payload: { progress: 0.4, forward: true, duration: 103 },
    })
  })
})
