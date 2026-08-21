<div align="center">

# 🍃 Leeef Reader
### *开卷新境，伴读以灵 · Turn a new leeef with AI*

**一款为 AI 时代打造的跨平台（iOS / Android / macOS / Windows）深度共读工作台。**  
**集成物理级 3D 仿真翻页、MCP (Model Context Protocol) 智能体生态与 S3 离线优先云同步。**

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Platform](https://img.shields.io/badge/Platform-iOS%20|%20Android%20|%20macOS%20|%20Windows-green.svg)](#)
[![Website](https://img.shields.io/badge/Official%20Website-leeefreader.org-blueviolet.svg)](https://leeefreader.org)

</div>

---

## 🎯 项目定位：从“阅读器”到“AI 知识工作台”

市面上绝大多数电子书阅读器仍然停留在上一代**“单向文本展示”**的思维中。即便部分软件加入了 AI，也仅仅是预设了几个翻译或总结的死板 Prompt，数据依然是孤岛。

**Leeef Reader 的核心定位是一个「AI-Native 个人知识引擎与深度共读工作台」：**

1. **阅读体验回归物理质感**：基于纯原生 Canvas 与 Shader 打造极致丝滑的 **3D 仿真卷角翻页（Page Curl）**，重现指尖触碰纸张的沉浸阅读感。
2. **MCP (Model Context Protocol) 原生赋能**：不仅能在阅读时让 AI 调用外部工具（制卡 Anki、写入 Obsidian、实时学术检索），还能**将书库作为 MCP Server 暴露给电脑上的 Cursor / Codex / Claude Desktop**，让代码与写作随时引用书摘。
3. **S3 云原生与离线优先（Own Your Data）**：告别老旧脆弱的 WebDAV，采用现代 **S3 对象存储协议（兼容 Cloudflare R2 / MinIO / AWS S3 / 阿里云 OSS）**。**零中心服务器依赖**，书籍与笔记 100% 属于用户自己。
4. **真正的现代四端一体**：单一 Flutter 代码库，无缝覆盖 **iOS、Android、macOS、Windows**。

---

## 🌟 核心特性与杀手级功能

### 1. 📖 物理级 3D 仿真翻页与多格式排版
* **纯原生渲染**：采用 Canvas + 贝塞尔曲线几何形变与动态光影着色，拒绝卡顿与掉帧，在移动端和桌面端均保持 120Hz 满帧手势跟手体验。
* **全格式支持**：深度解析 **EPUB、PDF、TXT**，支持自定义排版、多栏切换与字体渲染。
* **PDF 深度交互**：基于 PDFium 引擎，支持原生高精度文本划词、目录大纲导航、选区批注。

### 2. 🤖 MCP (Model Context Protocol) 双向智能体
* **作为 MCP Client（伴读增强）**：
  * **联动第二大脑**：读到重点概念，AI 自动调用 MCP 检索你的本地 **Obsidian / Notion** 历史笔记并做双向关联。
  * **划词一键制卡**：选中生词或考点，AI 自动提炼例句语法，直接通过 MCP 推送到 **Anki**。
  * **实时事实核查**：非虚构与学术书籍阅读中，AI 自动调用 **Brave / ArXiv / 维基百科 MCP** 展开深度背景。
* **作为 MCP Server（外脑输出）**：
  * 外部 Agent（Cursor / Codex / Claude Desktop）可通过 MCP 直接搜索并调取你在 Leeef Reader 中沉淀的数千条高亮书摘与书籍原文。

### 3. ☁️ S3 离线优先云同步与导出
* **现代 S3 协议**：支持分片上传、断点续传与基于哈希（SHA-256）的书籍秒传去重。
* **离线优先架构（Offline-First）**：无网状态下阅读、划线丝滑无阻；联网后基于 Drift 数据库与 S3 增量日志自动同步阅读进度与书签。
* **多维导出体系**：一键生成精美金句排版卡片（PNG），支持完整导出为 Markdown、Notion 格式与 JSON 备份。

### 4. 🔒 极致私密与零服务器（BYOS + BYOK）
* **0 追踪、0 遥测、0 中心服务器**。
* **BYOS（自带存储）**：使用免费的 Cloudflare R2（10GB 永久免费）或自有 NAS MinIO 存储书库。
* **BYOK（自带 Key）**：客户端直连 **DeepSeek、OpenAI、Claude、Gemini、本地 Ollama** 等大模型，全流式（SSE）响应。

---

## 🏛️ 现代架构核心：Riverpod + Drift + S3 + MCP

Leeef Reader 彻底摒弃了上一代阅读器“自建重度后端、弱本地存储、僵死 Prompt”的传统范式，采用专为 AI 时代打造的 **「现代四支柱协同架构」**：

| 核心支柱 | 角色定位 | 解决什么核心问题？ |
| :--- | :--- | :--- |
| 🧠 **Riverpod** | **神经中枢（响应式状态管理）** | 天然支持大模型 **SSE 逐字流式返回** 与异步流监听，编译期类型安全，业务逻辑与 UI 彻底解耦。 |
| 💾 **Drift (SQLite)** | **本地记忆（离线优先单一真实来源）** | 强类型响应式 ORM。自带 `watch()` 机制——**S3 后台增量同步一旦写入，屏幕 UI 自动秒级刷新**，无网离线体验极速丝滑。 |
| ☁️ **S3 协议** | **云端仓库（零服务器去中心化存储）** | 兼容 **Cloudflare R2 / MinIO / AWS S3 / OSS**。开发者 0 服务器运维负担，用户数据 100% 自主掌控（BYOS），支持大文件哈希秒传与分片续传。 |
| 🔌 **MCP 协议** | **手与眼（开放智能体上下文协议）** | 接入 Anthropic 开源标准。双向打通——**既让阅读器 AI 能调用外部工具（Obsidian/Anki），又让外部 AI（Cursor/Codex）能调取阅读器书摘**。 |

```
+-----------------------------------------------------------------------------------+
|                        🍃 Leeef Reader Client (Flutter)                           |
|                                                                                   |
|  [ 表现层 UI ]     : 3D 仿真翻页 (page_flip) / PDF 原生划词 (pdfrx) / AI 聊天流式气泡  |
|  [ 1. 状态中枢 ]   : Riverpod (编译期安全、响应式 Stream 数据流动、解耦业务)           |
|  [ 2. 本地记忆底座 ] : Drift SQLite (响应式 watch() 查询、离线优先单一真实来源)         |
|  [ 3. AI 与 MCP 引擎]: Multi-LLM 聚合调度器 (SSE 流式) + MCP Client/Server 协议解析器 |
|  [ 4. S3 存储引擎 ] : minio_new (纯 Dart 跨端 S3 客户端，断点续传与元数据同步)          |
+-----------------------------------------------------------------------------------+
                                   │              │
                   ┌───────────────┘              └───────────────┐
                   ▼                                              ▼
       [ S3 现代对象存储 ]                               [ 开放 AI & MCP 生态 ]
  (Cloudflare R2 / MinIO / AWS S3)               (DeepSeek / Claude / OpenAI / Tools)
```

---

## 📦 核心技术栈清单 (Tech Stack Blueprint)

| 模块类别 | 选用技术 / 核心库 | 选型理由与技术价值 |
| :--- | :--- | :--- |
| **跨端框架** | **Flutter (Dart)** | 真正的 iOS / Android / macOS / Windows 四端原生编译，高帧率 Skia/Impeller 渲染底座。 |
| **状态管理** | **`flutter_riverpod`** | 现代 Flutter 事实标准，天然契合大模型 SSE 流式数据推送与跨模块状态解耦。 |
| **本地数据库** | **`drift`** + **`sqlite3_flutter_libs`** | 强类型 SQLite ORM，支持响应式 `watch()`（S3 同步完本地 UI 自动无感刷新）。 |
| **3D 仿真翻页** | **`page_flip`** + 自研 Canvas 引擎 | 贝塞尔物理形变算法与着色器，提供 120Hz 纸质卷角翻页手感。 |
| **PDF 阅读引擎** | **`pdfrx`** | 基于 Google PDFium 引擎，支持全平台高性能渲染、原生高精度文字划词与搜索。 |
| **EPUB 排版解析** | **`epubx`** | 纯 Dart 实现的 EPUB 深度解析器，支持目录大纲、章节流式解压与样式重排。 |
| **S3 协议客户端** | **`minio_new`** | 纯 Dart 实现的完整 S3 协议库，无原生依赖，完美支持 R2 / MinIO / S3 / 阿里云 OSS。 |
| **大模型接入** | **`dart_openai`** + **`dio`** | 兼容所有 OpenAI 格式大模型（DeepSeek / Moonshot / Ollama），支持高并发 SSE 流式解析。 |
| **MCP 协议通信** | **`json_rpc_2`** + 进程管道/SSE | 实现 Anthropic MCP 协议标准（桌面端支持 `stdio` 本地进程，全端支持 `SSE` 远程连接）。 |
| **卡片与文件导出** | **`screenshot`** + **`file_saver`** | 跨端 Widget 像素级渲染转高清 PNG 书摘卡片，多平台系统级文件另存为。 |

---

## 🗺️ 开发路线图 (Roadmap)

- [ ] **Phase 1: 核心排版与仿真翻页引擎**
  - [ ] TXT / EPUB 流式切页算法与字号动态重排
  - [ ] 移动端触控与桌面端拖拽的 3D 卷角仿真翻页实现
  - [ ] 基于 `pdfrx` 的 PDF 渲染与划词交互
- [ ] **Phase 2: 本地 SQLite 离线优先与 S3 云同步**
  - [ ] Drift 本地书库、高亮、书签与阅读进度数据建模
  - [ ] S3 (Cloudflare R2 / MinIO) 认证、书籍上传下载与增量同步
- [ ] **Phase 3: AI 流式伴读与划词深度交互**
  - [ ] 多服务商 API Key 配置（DeepSeek, OpenAI, Claude, Gemini, Ollama）
  - [ ] 划词悬浮菜单：AI 深度解释、章节脉络总结、精美卡片生成
- [ ] **Phase 4: MCP (Model Context Protocol) 深度集成**
  - [ ] MCP Client：集成 Obsidian、Anki、Brave 搜索工具
  - [ ] MCP Server：向桌面端 Cursor / Codex 暴露书库检索接口
- [ ] **Phase 5: 全平台构建与公开发布**
  - [ ] macOS / Windows 桌面端适配与键盘快捷键
  - [ ] iOS / Android 移动端触控优化
  - [ ] 开源发布与官网 [leeefreader.org](https://leeefreader.org) 上线

---

## 📄 开源许可证

本项目采用商业友好的 **[Apache License 2.0](LICENSE)** 协议开源。
