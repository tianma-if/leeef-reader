<div align="center">

# 🍃 Leeef Reader
### *Turn a new leeef with AI.*

**An AI-native, cross-platform e-book workspace with realistic 3D page flip, MCP agent tools, and S3-compatible cloud synchronization.**

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Platform](https://img.shields.io/badge/Platform-iOS%20|%20Android%20|%20macOS%20|%20Windows-green.svg)](#)
[![Website](https://img.shields.io/badge/Website-leeefreader.org-blueviolet.svg)](https://leeefreader.org)

</div>

---

## 🌟 Highlights

- **📖 Realistic 3D Page Flip (仿真翻页)**: Pure Canvas & Shader-accelerated page curling and dynamic lighting, offering physical-grade reading tactile feedback on touchscreens and desktop.
- **🤖 MCP (Model Context Protocol) Native**: Seamlessly integrates Model Context Protocol as both an MCP Client (calling Obsidian, Anki, web search) and an MCP Server (exposing your book highlights to Cursor/Claude).
- **🧠 Multi-LLM Companion**: Native streaming (SSE) support for OpenAI, Claude, DeepSeek, Google Gemini, and local Ollama models.
- **☁️ S3 Cloud Sync (Offline-First)**: Full compatibility with AWS S3, Cloudflare R2, MinIO, and Aliyun OSS. Read offline anytime; sync reading progress, highlights, and book files seamlessly.
- **💻 True Multi-Platform**: Single codebase powering iOS, Android, macOS, and Windows.
- **🔒 Sovereign & Private (BYOS + BYOK)**: Zero tracking, zero telemetry. Bring your own S3 storage and LLM API keys.

---

## 🏗️ Architecture Blueprint

```
+-----------------------------------------------------------------------------------+
|                           🍃 Leeef Reader Client (Flutter)                        |
|                                                                                   |
|  [ UI Layer ]        : 3D Page Flip (page_flip) / PDF Viewer (pdfrx) / AI Chat UI |
|  [ State Layer ]     : Riverpod Reactive State Management                         |
|  [ Local Storage ]   : Drift (Reactive SQLite ORM, Offline-First)                 |
|  [ AI & MCP Layer ]  : Multi-Provider LLM Engine + MCP Host/Client Engine        |
|  [ Cloud Sync Layer] : S3 Protocol Engine (minio_new)                             |
+-----------------------------------------------------------------------------------+
                                   │              │
                   ┌───────────────┘              └───────────────┐
                   ▼                                              ▼
       [ S3 Object Storage ]                             [ LLM & MCP Ecosystem ]
  (Cloudflare R2 / MinIO / AWS S3)               (DeepSeek / Claude / OpenAI / Tools)
```

---

## 📦 Tech Stack

- **Framework**: [Flutter](https://flutter.dev) (Dart)
- **State Management**: [Riverpod](https://riverpod.dev)
- **Local Database**: [Drift (SQLite)](https://drift.simonbinder.eu/)
- **PDF Engine**: [pdfrx](https://pub.dev/packages/pdfrx)
- **EPUB Engine**: [epubx](https://pub.dev/packages/epubx)
- **S3 Protocol**: [minio_new](https://pub.dev/packages/minio_new)
- **AI / MCP**: [dart_openai](https://pub.dev/packages/dart_openai) + [json_rpc_2](https://pub.dev/packages/json_rpc_2)

---

## 🗺️ Roadmap

- [ ] **Phase 1**: Core Reading Engine (TXT/EPUB/PDF pagination & 3D page flip animation)
- [ ] **Phase 2**: S3 Multi-Device Sync (Book files & reading progress)
- [ ] **Phase 3**: In-App AI Reader Companion (Streaming chat, highlight explanation, summary)
- [ ] **Phase 4**: Full MCP Client & Server Integration (Obsidian, Anki, Cursor/Claude integration)
- [ ] **Phase 5**: Cross-platform Releases (iOS, macOS, Android, Windows)

---

## 📄 License

Licensed under the [Apache License, Version 2.0](LICENSE).
