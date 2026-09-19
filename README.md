<div align="center">

# 🍃 Leeef Reader

**跨端同步、MCP 原生、移动端支持滑动翻页的电子书阅读器。**

iOS · Android · macOS · Windows

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)

</div>

当前主线是 **Tauri 2 + React + foliate-js**（系统 WebView）。Flutter 客户端已从仓库移除，历史仍可在 git 里查到。

## 开发

```bash
cd apps/reader
npm install
npm run tauri dev
```

Android 真机：

```bash
cd apps/reader
npx tauri android build --debug --apk --target aarch64
```

只使用 USB 真机，不要开模拟器。说明见 [`docs/tauri-reader.md`](docs/tauri-reader.md)。

MCP sidecar：

```bash
cd sidecars/leeef-mcp
go test ./...
```

应用设置页可启动 sidecar，并指向本地 `leeef.sqlite`。

## 产品范围

书架、阅读（EPUB / TXT / MOBI / AZW3 / FB2 / PDF）、笔记、统计、OPDS、TTS、AI 设置、配对码。同步引擎（S3/WebDAV、扫码配对）和商店流水线正在从 Flutter 迁到这条栈上。

## License

AGPL-3.0
