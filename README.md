<div align="center">

# 🍃 Leeef Reader

**跨端同步、MCP 原生、移动端支持 3D 仿真翻页的电子书阅读器。**

iOS · Android · macOS · Windows

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Status: Early Development](https://img.shields.io/badge/Status-Early_Development-orange.svg)](#项目状态)

</div>

## 核心能力

### 1. 跨端同步

以下数据在 iOS、Android、macOS 和 Windows 之间保持一致：

| 数据 | 同步内容 |
| --- | --- |
| 书籍文件 | EPUB、MOBI、AZW3、FB2、TXT、PDF 原文件、封面和元数据 |
| 阅读进度 | 当前章节、页码、阅读位置和更新时间 |
| 书摘 | 高亮原文、笔记、颜色和原文定位 |
| 书签 | 书签位置、标题和备注 |
| 书架目录 | 书架、目录层级、排序和书籍归属 |

应用离线时正常读写；恢复网络后自动同步。书籍文件按 SHA-256 去重，元数据通过增量操作日志同步，不直接上传或覆盖 SQLite 数据库文件。

### 2. MCP 全量管理

Leeef 通过 MCP 向 AI 暴露完整书库，并允许 AI 在用户授权后执行管理操作。

> MCP 不保存数据。AI 通过 MCP 修改本地数据库，修改结果再由同步引擎传播到其他设备。

```text
AI / Codex / Claude
        │
        ▼
    leeef-mcp
        │
        ▼
 Drift / SQLite ──→ Sync Engine ──→ 其他设备
```

计划提供的 MCP Resources：

```text
leeef://library
leeef://books/{bookId}
leeef://books/{bookId}/content
leeef://books/{bookId}/excerpts
leeef://books/{bookId}/bookmarks
leeef://bookshelves/{bookshelfId}
```

计划提供的 MCP Tools：

```text
# 书籍
list_books
search_books
get_book
get_book_content
update_book_metadata
move_book
delete_book

# 书摘
list_excerpts
search_excerpts
create_excerpt
update_excerpt
delete_excerpt

# 书签
list_bookmarks
create_bookmark
update_bookmark
delete_bookmark

# 书架目录
list_bookshelves
create_bookshelf
rename_bookshelf
move_bookshelf
delete_bookshelf
add_book_to_bookshelf
remove_book_from_bookshelf

# 阅读进度
get_reading_progress
update_reading_progress
```

删除书籍、批量移动等高风险写操作需要显式确认，并记录调用方、参数、时间和执行结果。

### 3. 移动端交互式 3D 翻页

3D Page Curl 是 iOS 和 Android 的核心阅读能力：

- 支持拖拽、回弹、甩页和取消
- 针对触控手势和不同屏幕尺寸优化
- 支持 EPUB、MOBI、AZW3、FB2、TXT 和 PDF
- 支持单页、双页与横竖屏布局
- 翻页时预渲染相邻页面，避免动画帧内重新排版
- 60fps 为基础目标，高刷新率设备针对 120Hz 优化

翻页引擎采用页面纹理与 Fragment Shader 实现，不依赖通用翻页 Widget。macOS 和 Windows 不实现 3D Page Curl，提供滑动、无动画和连续滚动模式。

## 功能树

以下均为 Leeef 的目标功能，采用分阶段实现。除 MCP 和移动端 3D Page Curl 外，功能范围以 Anx Reader 当前已实现能力为兼容基线；OPDS 单独列为后续能力。

```text
Leeef Reader
├── 书籍与书库
│   ├── 格式：EPUB、MOBI、AZW3、FB2、TXT、PDF
│   ├── 导入：单本/批量选择、桌面拖拽、移动端分享导入
│   ├── 元数据：自动提取标题、作者、简介和封面
│   ├── TXT：编码识别、自定义章节切分、自动转换
│   ├── 去重：MD5/SHA-256 检测、重复文件处理
│   ├── 书架：网格、文件夹/分组、拖拽移动、重命名和解散
│   ├── 标签：创建、改名、颜色、删除、批量归类
│   ├── 筛选：未开始、阅读中、已读完、标签/无标签
│   ├── 排序：标题、作者、最近阅读、进度、导入时间、升降序
│   ├── 详情：编辑元数据和封面、评分、进度、时长和日期
│   └── 文件：分享、替换、删除、释放本地空间、云端重新下载
│
├── 阅读器
│   ├── 模式：分页、滑动、无动画、连续滚动、单栏/双栏
│   ├── 排版方向：横排、竖排、横竖屏
│   ├── 导航：多级目录、当前章节定位、进度跳转、前进/后退历史
│   ├── 定位：CFI、章节页码、全书进度、书签跳转
│   ├── 搜索：书内全文搜索、按章节展示结果、跳转原文
│   ├── 内容：图片查看、脚注弹层、外链确认、复制章节正文
│   ├── 操作：自定义点击区域、左右互换、音量键、键盘和滚轮翻页
│   ├── 桌面交互：鼠标、触控板、Hover 菜单、右键菜单和快捷键
│   └── 阅读状态：自动保存位置、全屏、常亮、可配置页眉页脚
│
├── 阅读样式
│   ├── 字体：系统/书籍/导入字体、字号、字重、标题字号
│   ├── 排版：行距、段距、字距、缩进、边距和文本对齐
│   ├── 书籍样式：保留或忽略原始 CSS、自定义 CSS 和校验
│   ├── 主题：前景色、背景色、日间/夜间背景图
│   ├── 背景效果：模糊、透明度、填充方式、自动明暗适配
│   ├── 显示：OLED 黑色模式、电子墨水屏模式
│   ├── 代码：语法高亮和明暗主题
│   └── 中文：简体、繁体和原文显示转换
│
├── 书签、书摘与笔记
│   ├── 书签：添加、删除、列表、原文跳转
│   ├── 书摘：高亮/下划线、多颜色、修改和删除
│   ├── 阅读笔记：为书摘添加想法、编辑、删除、批量操作
│   ├── 笔记工作区：按书汇总、按时间/章节排序、颜色/类型筛选
│   ├── 导出：剪贴板、Markdown、TXT、CSV、章节合并
│   └── 分享卡片：多模板、字体、颜色、背景、保存图片和系统分享
│
├── 选中文本操作
│   ├── 复制、Web 搜索、翻译/词典、从当前位置朗读
│   ├── 创建书摘、选择标记样式、撰写笔记
│   └── 发送给 AI、生成分享卡片
│
├── TTS 朗读
│   ├── 服务：系统 TTS、阿里云、Azure、OpenAI
│   ├── 声音：声音模型、音量、语速和音调
│   ├── 控制：播放、暂停、停止、上一句、下一句、睡眠定时
│   └── 体验：当前句高亮、自动跟随、系统媒体控制、音频混音
│
├── AI 阅读助手
│   ├── 对话：全局书库、阅读页上下文、弹窗/分栏/自适应显示
│   ├── 阅读：章节总结、全书总结、回顾前文、分析和思维导图
│   ├── 书库：查询和整理书架、搜索正文/笔记、阅读历史、标签管理
│   ├── 上下文：当前书籍、目录、章节和指定章节正文
│   ├── 翻译
│   │   ├── 划词：结合原文上下文进行翻译和词典式解释
│   │   ├── 全文：原文、译文、双语对照、长文本分段和进度控制
│   │   ├── 质量：术语表、人名一致性、语气保持和上下文衔接
│   │   ├── 可靠性：译文缓存、失败重试、取消和低成本模型选择
│   │   └── Provider：首期仅实现 `LlmTranslationProvider`，复用 AI 模型配置
│   ├── 模型：OpenAI-compatible、Claude、Gemini、DeepSeek、OpenRouter
│   ├── 配置：自定义 API、模型、多 API Key 轮换、推理强度和连通测试
│   ├── Prompt：编辑内置 Prompt、添加用户 Prompt
│   └── Tools：独立开关、结构化结果、整理计划确认后执行
│
├── 阅读统计
│   ├── 记录：阅读时长、阅读天数、连续阅读、书籍数和笔记数
│   ├── 视图：周、月、年、全部时间、阅读热力图
│   ├── 分析：7/30 日趋势、完成度、阅读最多的书、阶段汇总
│   ├── 回顾：随机书摘、继续阅读
│   ├── 仪表盘：统计卡片增加、删除和排序
│   └── 数据：阅读记录编辑、删除和撤销
│
├── 跨端同步与备份
│   ├── 后端：默认 S3-compatible，可选 WebDAV
│   ├── 策略：自动/手动同步、仅 Wi-Fi、能力检测和完成通知
│   ├── 数据：书籍、封面、进度、书摘、笔记、书签、目录、标签、统计
│   ├── 云端书籍：状态展示、批量下载、释放本地空间
│   ├── 可靠性：增量操作、幂等应用、冲突合并、删除标记和完整性校验
│   └── 数据保护：备份、恢复、失败回滚、全量导出和导入
│
├── MCP 原生管理（Leeef）
│   ├── Resources：书库、书籍正文、书摘、书签和书架目录
│   ├── Tools：查询、创建、更新、移动、归类和删除
│   ├── 写操作：plan → confirm → apply
│   └── 安全：权限、调用审计、幂等 operationId
│
├── 移动端 3D Page Curl（Leeef）
│   ├── 平台：iOS、Android
│   ├── 手势：拖拽、回弹、甩页和取消
│   ├── 渲染：相邻页预渲染、双页纹理、Fragment Shader
│   └── 性能：60fps 基线、高刷新率优化
│
├── 全局搜索
│   ├── 书名和作者
│   ├── 书摘和笔记
│   └── 搜索结果跳转书籍或原文
│
├── 外观与平台能力
│   ├── Material 3 响应式布局、明暗主题和自定义主题色
│   ├── 移动端底部导航、桌面端 NavigationRail 和多栏布局
│   ├── 多语言、导航栏目显隐、书架封面和文件夹样式
│   ├── 桌面窗口尺寸/位置恢复、拖拽、键鼠和触控板
│   └── 震动反馈、开书动画、更新检查和变更日志
│
├── 数据与高级设置
│   ├── 存储统计、缓存清理、文件明细和字体管理
│   ├── 自定义数据目录和数据迁移
│   ├── MD5 补算、缺失文件检查、数据库迁移
│   ├── EPUB JavaScript 开关、HTTP 代理、日志查看和清理
│   └── 新手引导、提示重置和开发者选项
│
└── OPDS（后续）
    ├── OPDS 目录订阅
    ├── 自定义目录管理
    ├── 浏览、搜索和下载
    └── 导入书架与同步衔接
```

## 技术架构

```text
┌──────────────────────────── Flutter App ────────────────────────────┐
│                                                                     │
│  foliate-js/WebView      pdfrx/PDFium       TXT Layout              │
│            └─────────────────┬────────────────┘                       │
│                              ▼                                       │
│                     Unified Page Model                               │
│               页面纹理 · 文本范围 · CFI · 命中区域                    │
│                              │                                       │
│                  ┌───────────┴───────────┐                           │
│                  ▼                       ▼                           │
│       Mobile PageCurlEngine      Desktop Page Navigation             │
│                                                                     │
│  Riverpod ───── Drift/SQLite/FTS5 ───── Sync Engine                 │
│                                │                 │                  │
└────────────────────────────────┼─────────────────┼──────────────────┘
                                 │                 │
                                 ▼                 ▼
                            leeef-mcp       SyncBackend
                                              ├── S3
                                              └── WebDAV
```

## 技术选型

| 模块 | 方案 |
| --- | --- |
| 跨端框架 | Flutter / Dart |
| UI 框架 | Flutter Material 3，iOS、Android、macOS、Windows 共用一套组件体系 |
| 主题系统 | `ColorScheme` + `ThemeExtension`，统一颜色、字体、间距、圆角和动效 |
| 平台适配 | 移动端侧重触控和底部导航；桌面端增加多栏布局、键鼠、右键菜单和窗口适配 |
| 阅读界面 | 基于统一 Material 主题自研阅读组件，不引入第二套 UI 框架 |
| 状态管理 | `flutter_riverpod` |
| 本地数据库 | `drift` + `drift_flutter` + SQLite FTS5 |
| 流式电子书排版 | 内置 `foliate-js` + `flutter_inappwebview`，封装为 `ReaderEngine` |
| 格式支持 | EPUB、MOBI、AZW3、FB2、TXT、PDF；首期优先 EPUB、PDF、TXT |
| WebView 资源服务 | 随机端口 loopback HTTP Server + session token + `bookId` 路径白名单 |
| PDF | `pdfrx` / PDFium |
| 移动端 3D 翻页 | iOS / Android 自研 `PageCurlEngine` + Flutter Fragment Shader |
| 桌面端翻页 | macOS / Windows 支持滑动、无动画和连续滚动，不实现 3D Page Curl |
| 移动端页面快照 | foliate-js 相邻页预渲染、PDF bitmap、原生 WebView Snapshot Adapter |
| 同步接口 | 自研 `SyncBackend`，统一对象读写、列举、条件写入与能力检测 |
| 默认同步后端 | S3 兼容对象存储 |
| 可选同步后端 | WebDAV，面向 NAS、Nextcloud 等自托管场景 |
| S3 签名 | `aws_common` + `aws_signature_v4` |
| 凭证存储 | `flutter_secure_storage` |
| MCP Server | Go + 官方 MCP Go SDK，编译为桌面端单文件 sidecar |
| MCP Client | Dart + `dio`，支持 Streamable HTTP |
| AI/MCP 工具层 | 统一 JSON Schema Tool Registry；高风险写操作采用 `plan → confirm → apply` |
| AI 翻译 | 统一 `TranslationProvider` 抽象，首期仅实现 `LlmTranslationProvider` |

## 同步设计

不同同步后端使用相同的逻辑对象结构：

```text
blobs/{sha256}/original            书籍原文件
blobs/{sha256}/cover               封面
ops/{deviceId}/{ulid}.json         增量操作
checkpoints/{deviceId}.json        同步水位
```

S3 是默认后端；WebDAV 作为可选适配器。启动同步前执行能力检测，确认目录创建、上传、下载、条件写入和删除行为。同步后端只保存不可变文件、操作日志与水位，不上传或覆盖 SQLite 数据库文件。

同步引擎负责：

- 幂等应用操作
- 多设备冲突检测与合并
- 删除标记和恢复
- ETag/版本号条件写入
- 断点续传
- 日志压缩
- 数据完整性校验

默认冲突规则：

| 数据 | 规则 |
| --- | --- |
| 阅读进度 | 采用更新时间较新的有效进度，保留设备历史用于恢复 |
| 书摘、书签 | 使用稳定 ID 合并；不同 ID 不互相覆盖 |
| 书架目录 | 使用稳定 ID 和父目录 ID 合并；冲突操作写入审计日志 |
| 书籍文件 | 按内容哈希不可变存储，相同文件不重复上传 |

## 功能优先级

功能树是长期范围，不代表首版范围。优先级按“是否能证明 Leeef 的独立价值”划分：

| 优先级 | 目标 | 发布要求 |
| --- | --- | --- |
| P0 | 证明产品成立 | 缺少任何一项都不发布首个可用版本 |
| P1 | 达到日常主力阅读器水平 | P0 稳定后逐项交付 |
| P2 | 完成 Anx Reader 功能兼容并扩展生态 | 不阻塞核心产品发布 |

### P0：产品成立

只实现“阅读 + 同步 + MCP + 移动端 3D 翻页”的完整闭环：

- 四端 Material 3 应用骨架和统一数据模型
- EPUB、PDF、TXT 导入、书架和基础阅读
- 阅读进度、书摘、书签、书架目录本地管理
- 基础字体、字号、行距、主题、目录、进度和书内搜索
- iOS / Android 交互式 3D Page Curl
- macOS / Windows 滑动、无动画和连续滚动
- S3 `SyncBackend`：五类核心数据和书籍文件的增量同步
- UUID/ULID、操作日志、幂等、删除标记、冲突合并和失败恢复
- `leeef-mcp`：核心 Resources、查询 Tools 和管理 Tools
- MCP 高风险操作的 `plan → confirm → apply`、权限和审计
- 基础数据导出、备份恢复和四端自动化验证

P0 验收标准：

1. 任一设备新增书摘、书签或调整目录，其他设备能正确合并并恢复现场。
2. AI 能通过 MCP 查询正文和阅读数据，并在确认后移动书籍、修改书摘或书签。
3. MCP 修改能通过同步引擎传播到其他设备，不绕过操作日志。
4. iOS 和 Android 的 3D Page Curl 在目标设备上稳定达到 60fps，失败时可降级为普通翻页。

### P1：日常主力阅读器

- MOBI、AZW3、FB2 格式支持
- WebDAV `SyncBackend`、仅 Wi-Fi 同步和云端书籍按需下载
- 标签、评分、高级筛选排序、文件替换和批量书架管理
- 笔记工作区及 Markdown、TXT、CSV 导出
- 更多字体、排版、背景和自定义阅读样式
- 全局搜索、基础阅读统计和热力图
- 系统 TTS；AI 助手的基础模型 Provider、上下文划词翻译和简繁转换
- 桌面端键鼠、右键菜单、拖拽、多栏和窗口状态完善
- 移动端分享导入、后台同步和功耗优化

### P2：完整功能与生态

- 阿里云、Azure、OpenAI TTS，多声音模型和睡眠定时
- AI 助手的全文翻译、双语对照、术语一致性和译文缓存
- AI 助手的应用内对话、章节/全书总结、前文回顾和思维导图
- AI Provider、Prompt、多 API Key 轮换和可配置 Tool Registry
- 分享卡片、高级统计仪表盘和随机书摘回顾
- 自定义 CSS、代码高亮、OLED 和电子墨水屏模式
- 多语言界面、自定义存储目录、代理、日志和高级数据工具
- OPDS 目录订阅、浏览、搜索和下载

## 开发路线图

### M0：高风险技术验证

- [ ] foliate-js 四端加载、排版、CFI 和文本选择
- [ ] iOS / Android WebView 相邻页预渲染、快照和 Shader 原型
- [ ] Drift 数据模型、操作日志和双设备冲突模拟
- [ ] MCP sidecar 与 Flutter 本地数据通路

只有四项验证全部通过，才进入完整功能开发。

### M1：P0 纵向闭环

- [ ] 完成单本书从导入、阅读、摘录到同步的完整流程
- [ ] 完成 MCP 查询、确认写入和跨端同步流程
- [ ] 完成移动端 3D Page Curl 与普通翻页降级
- [ ] 完成四端数据完整性、离线和故障恢复测试

### M2：P1 日常可用

- [ ] 扩展格式、WebDAV、书库管理和笔记导出
- [ ] 完善阅读样式、搜索、基础统计、系统 TTS 和 AI 上下文划词翻译
- [ ] 完善移动端与桌面端平台交互

### M3：P2 功能兼容与生态

- [ ] 完成多服务 TTS，以及 AI 助手的全文翻译和应用内对话
- [ ] 完成高级统计、分享、样式和数据工具
- [ ] 完成 OPDS 与多语言支持
- [ ] 持续进行性能、可访问性、数据迁移和发布质量建设

## 项目状态

项目处于早期开发阶段，当前阶段为 **M0：高风险技术验证**。首个可用版本严格限定为 P0，不因功能树中的 P1/P2 项目扩大范围。

## 许可证

本项目采用 [Apache License 2.0](LICENSE) 开源。
