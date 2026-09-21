import { invoke } from '@tauri-apps/api/core'

export async function saveTextExport(filename: string, content: string): Promise<boolean> {
  const result = await invoke<{ saved: boolean }>('plugin:native-bridge|save_text_file', {
    payload: { filename, content },
  })
  return result.saved
}
