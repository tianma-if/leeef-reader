export type ReadingFontGroup = 'publisher' | 'reading' | 'system'

export type ReadingFont = {
  id: string
  label: string
  group: ReadingFontGroup
  family: string
  stack: string
  files: string[]
  sample: string
}

export const DEFAULT_FONT_ID = 'noto-serif-sc'

export const READING_FONTS: ReadingFont[] = [
  {
    id: 'publisher',
    label: '书籍原字体',
    group: 'publisher',
    family: '',
    stack: 'Georgia, "Songti SC", "Noto Serif CJK SC", "Source Han Serif SC", serif',
    files: [],
    sample: '保持排版',
  },
  {
    id: 'noto-serif-sc',
    label: '思源宋体',
    group: 'reading',
    family: 'Noto Serif SC',
    stack: '"Noto Serif SC", "Source Han Serif SC", "Songti SC", serif',
    files: [
      'noto-serif-sc/chinese-simplified.woff2',
      'noto-serif-sc/latin.woff2',
      'noto-serif-sc/latin-ext.woff2',
    ],
    sample: '落霞与孤鹜齐飞',
  },
  {
    id: 'noto-sans-sc',
    label: '思源黑体',
    group: 'reading',
    family: 'Noto Sans SC',
    stack: '"Noto Sans SC", "Source Han Sans SC", "PingFang SC", sans-serif',
    files: [
      'noto-sans-sc/chinese-simplified.woff2',
      'noto-sans-sc/latin.woff2',
      'noto-sans-sc/latin-ext.woff2',
    ],
    sample: '落霞与孤鹜齐飞',
  },
  {
    id: 'lxgw-wenkai',
    label: '霞鹜文楷',
    group: 'reading',
    family: 'LXGW WenKai',
    stack: '"LXGW WenKai", "Kaiti SC", "STKaiti", serif',
    files: ['lxgw-wenkai/regular.woff2'],
    sample: '落霞与孤鹜齐飞',
  },
  {
    id: 'zhuque-fangsong',
    label: '朱雀仿宋',
    group: 'reading',
    family: 'Zhuque Fangsong',
    stack: '"Zhuque Fangsong", FangSong, STFangsong, serif',
    files: ['zhuque-fangsong/regular.ttf'],
    sample: '落霞与孤鹜齐飞',
  },
  {
    id: 'literata',
    label: 'Literata',
    group: 'reading',
    family: 'Literata',
    stack: 'Literata, Georgia, "Noto Serif SC", serif',
    files: ['literata/latin.woff2', 'literata/latin-ext.woff2'],
    sample: 'A quick brown fox',
  },
  {
    id: 'sys-sans',
    label: '系统黑体',
    group: 'system',
    family: '',
    stack: '"PingFang SC", "HarmonyOS Sans SC", "Noto Sans CJK SC", "Microsoft YaHei", sans-serif',
    files: [],
    sample: '清风徐来',
  },
  {
    id: 'sys-serif',
    label: '系统宋体',
    group: 'system',
    family: '',
    stack: '"Songti SC", "Noto Serif CJK SC", SimSun, serif',
    files: [],
    sample: '清风徐来',
  },
  {
    id: 'sys-kai',
    label: '系统楷体',
    group: 'system',
    family: '',
    stack: '"Kaiti SC", STKaiti, KaiTi, serif',
    files: [],
    sample: '清风徐来',
  },
]

const byId = new Map(READING_FONTS.map((font) => [font.id, font]))

export const resolveFont = (value?: string): ReadingFont => {
  const trimmed = value?.trim()
  if (!trimmed) return byId.get(DEFAULT_FONT_ID)!
  const match = byId.get(trimmed) ?? READING_FONTS.find((font) => font.family === trimmed)
  if (match) return match
  return {
    id: 'custom',
    label: '自定义',
    group: 'publisher',
    family: trimmed,
    stack: trimmed,
    files: [],
    sample: trimmed,
  }
}

export const shouldOverrideBookFont = (font: ReadingFont) => font.id !== 'publisher'
