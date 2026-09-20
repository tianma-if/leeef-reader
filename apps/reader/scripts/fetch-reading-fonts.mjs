import { createWriteStream } from 'node:fs'
import { mkdir, writeFile, stat } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { pipeline } from 'node:stream/promises'
import { fileURLToPath } from 'node:url'
import { Readable } from 'node:stream'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const fontsDir = join(root, 'public', 'fonts')
const cdn = 'https://cdn.jsdelivr.net/npm'

const files = [
  {
    dest: 'noto-serif-sc/chinese-simplified.woff2',
    url: `${cdn}/@fontsource/noto-serif-sc@5.3.0/files/noto-serif-sc-chinese-simplified-400-normal.woff2`,
  },
  {
    dest: 'noto-serif-sc/latin.woff2',
    url: `${cdn}/@fontsource/noto-serif-sc@5.3.0/files/noto-serif-sc-latin-400-normal.woff2`,
  },
  {
    dest: 'noto-serif-sc/latin-ext.woff2',
    url: `${cdn}/@fontsource/noto-serif-sc@5.3.0/files/noto-serif-sc-latin-ext-400-normal.woff2`,
  },
  {
    dest: 'noto-sans-sc/chinese-simplified.woff2',
    url: `${cdn}/@fontsource/noto-sans-sc@5.3.0/files/noto-sans-sc-chinese-simplified-400-normal.woff2`,
  },
  {
    dest: 'noto-sans-sc/latin.woff2',
    url: `${cdn}/@fontsource/noto-sans-sc@5.3.0/files/noto-sans-sc-latin-400-normal.woff2`,
  },
  {
    dest: 'noto-sans-sc/latin-ext.woff2',
    url: `${cdn}/@fontsource/noto-sans-sc@5.3.0/files/noto-sans-sc-latin-ext-400-normal.woff2`,
  },
  {
    dest: 'lxgw-wenkai/regular.woff2',
    url: `${cdn}/@fontsource/lxgw-wenkai@5.3.0/files/lxgw-wenkai-latin-500-normal.woff2`,
  },
  {
    dest: 'zhuque-fangsong/regular.ttf',
    url: `${cdn}/@fontpkg/zhuque-fangsong-technical-preview@0.212.0/ZhuqueFangsong-Regular.ttf`,
  },
  {
    dest: 'literata/latin.woff2',
    url: `${cdn}/@fontsource/literata@5.3.0/files/literata-latin-400-normal.woff2`,
  },
  {
    dest: 'literata/latin-ext.woff2',
    url: `${cdn}/@fontsource/literata@5.3.0/files/literata-latin-ext-400-normal.woff2`,
  },
  {
    dest: 'licenses/OFL-noto-serif-sc.txt',
    url: `${cdn}/@fontsource/noto-serif-sc@5.3.0/LICENSE`,
  },
  {
    dest: 'licenses/OFL-noto-sans-sc.txt',
    url: `${cdn}/@fontsource/noto-sans-sc@5.3.0/LICENSE`,
  },
  {
    dest: 'licenses/OFL-lxgw-wenkai.txt',
    url: 'https://raw.githubusercontent.com/lxgw/LxgwWenKai/main/OFL.txt',
  },
  {
    dest: 'licenses/OFL-literata.txt',
    url: 'https://raw.githubusercontent.com/googlefonts/literata/main/OFL.txt',
  },
  {
    dest: 'licenses/OFL-zhuque-fangsong.txt',
    url: 'https://scripts.sil.org/cms/scripts/render_download.php?format=file&media_id=OFL_plaintext&filename=OFL.txt',
  },
]

const download = async (url, dest) => {
  const path = join(fontsDir, dest)
  await mkdir(dirname(path), { recursive: true })
  try {
    const existing = await stat(path)
    if (existing.size > 1024) {
      console.log(`skip ${dest} (${existing.size} bytes)`)
      return
    }
  } catch {
    // not present
  }
  console.log(`get  ${dest}`)
  const response = await fetch(url, { headers: { 'User-Agent': 'LeeefReader/2' } })
  if (!response.ok || !response.body) {
    if (dest.startsWith('licenses/')) {
      console.warn(`skip ${dest} (${response.status})`)
      return
    }
    throw new Error(`${response.status} ${url}`)
  }
  await pipeline(Readable.fromWeb(response.body), createWriteStream(path))
  const info = await stat(path)
  console.log(`ok   ${dest} (${info.size} bytes)`)
}

await mkdir(fontsDir, { recursive: true })
await writeFile(
  join(fontsDir, 'NOTICE.txt'),
  [
    'Bundled reading fonts are SIL Open Font License 1.1.',
    'Noto Serif SC / Noto Sans SC: Google / Adobe Source Han.',
    'LXGW WenKai: lxgw/LxgwWenKai.',
    'Zhuque Fangsong: TrionesType/zhuque (technical preview).',
    'Literata: Google Fonts.',
    'License texts are in licenses/.',
    '',
  ].join('\n'),
)

for (const file of files) {
  await download(file.url, file.dest)
}
