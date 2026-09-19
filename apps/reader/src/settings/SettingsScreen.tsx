import { useEffect, useState } from 'react'
import { api, type Settings } from '../api'

const desktop = !/Android|iPhone|iPad/i.test(navigator.userAgent)

export function SettingsScreen() {
  const [value, setValue] = useState<Settings>({})
  const [dbPath, setDbPath] = useState('')
  const [saved, setSaved] = useState('')

  useEffect(() => {
    void api.getSettings().then(setValue)
    void api.mcpDatabasePath().then(setDbPath)
  }, [])

  const patch = (next: Partial<Settings>) => setValue((current) => ({ ...current, ...next }))

  return (
    <main className="page">
      <header className="page-bar">
        <h1>设置</h1>
        <button
          type="button"
          className="btn"
          onClick={() =>
            void api.saveSettings(value).then(() => {
              setSaved('已保存')
              setTimeout(() => setSaved(''), 1500)
            })
          }
        >
          {saved || '保存'}
        </button>
      </header>

      <h2>阅读外观</h2>
      <label>
        主题
        <select
          value={value.theme ?? 'paper'}
          onChange={(event) => patch({ theme: event.target.value as Settings['theme'] })}
        >
          <option value="paper">纸张</option>
          <option value="sepia">护眼</option>
          <option value="night">夜间</option>
        </select>
      </label>
      <label>
        字号 {value.fontSize ?? 18}
        <input
          type="range"
          min={14}
          max={28}
          value={value.fontSize ?? 18}
          onChange={(event) => patch({ fontSize: Number(event.target.value) })}
        />
      </label>
      <label>
        行距 {value.lineHeight ?? 1.65}
        <input
          type="range"
          min={1.3}
          max={2.2}
          step={0.05}
          value={value.lineHeight ?? 1.65}
          onChange={(event) => patch({ lineHeight: Number(event.target.value) })}
        />
      </label>
      <label>
        排版
        <select
          value={value.flow ?? 'paginated'}
          onChange={(event) => patch({ flow: event.target.value as Settings['flow'] })}
        >
          <option value="paginated">分页</option>
          <option value="scrolled">连续滚动</option>
        </select>
      </label>
      <label>
        栏数
        <select
          value={value.columns ?? 1}
          onChange={(event) => patch({ columns: Number(event.target.value) as 1 | 2 })}
        >
          <option value={1}>单栏</option>
          <option value={2}>双栏</option>
        </select>
      </label>
      <label>
        中文
        <select
          value={value.chinese ?? 'original'}
          onChange={(event) =>
            patch({ chinese: event.target.value as Settings['chinese'] })
          }
        >
          <option value="original">原文</option>
          <option value="simplified">简体</option>
          <option value="traditional">繁体</option>
        </select>
      </label>

      <h2>TTS</h2>
      <label>
        语速 {value.ttsRate ?? 1}
        <input
          type="range"
          min={0.6}
          max={1.6}
          step={0.1}
          value={value.ttsRate ?? 1}
          onChange={(event) => patch({ ttsRate: Number(event.target.value) })}
        />
      </label>

      {desktop ? (
        <>
          <h2>AI（仅桌面填写）</h2>
          <label>
            Endpoint
            <input
              value={value.aiEndpoint ?? ''}
              onChange={(event) => patch({ aiEndpoint: event.target.value })}
              placeholder="https://api.openai.com/v1"
            />
          </label>
          <label>
            API Key
            <input
              type="password"
              value={value.aiKey ?? ''}
              onChange={(event) => patch({ aiKey: event.target.value })}
            />
          </label>
          <label>
            模型
            <input
              value={value.aiModel ?? ''}
              onChange={(event) => patch({ aiModel: event.target.value })}
              placeholder="gpt-4o-mini"
            />
          </label>
          <h2>同步</h2>
          <label>
            后端
            <select
              value={value.syncBackend ?? ''}
              onChange={(event) =>
                patch({ syncBackend: event.target.value as Settings['syncBackend'] })
              }
            >
              <option value="">未配置</option>
              <option value="s3">S3 兼容</option>
              <option value="webdav">WebDAV</option>
            </select>
          </label>
          <label>
            地址
            <input
              value={value.syncEndpoint ?? ''}
              onChange={(event) => patch({ syncEndpoint: event.target.value })}
            />
          </label>
          <p className="hint">手机通过桌面配对二维码同步这些凭据。写操作会记入 sync_operations，供 MCP 与多端同步使用。</p>
        </>
      ) : (
        <p className="hint">对象存储、AI 和 TTS 凭据只在桌面端填写，手机通过配对同步。</p>
      )}

      <h2>MCP</h2>
      <p className="hint">数据库路径：{dbPath || '…'}</p>
      <p className="hint">sidecar：`leeef-mcp --database {dbPath || 'leeef.sqlite'}`</p>
    </main>
  )
}
