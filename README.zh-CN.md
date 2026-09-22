<h1><img src="assets/brand/leeef-reader-logo.png" alt="Leeef Reader Logo" width="40" align="absmiddle" /> Leeef Reader</h1>

[![GitHub Stars](https://img.shields.io/github/stars/tianma-if/leeef-reader?style=social)](https://github.com/tianma-if/leeef-reader/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/tianma-if/leeef-reader?style=social)](https://github.com/tianma-if/leeef-reader/network/members)
[![GitHub Release](https://img.shields.io/github/v/release/tianma-if/leeef-reader?style=social)](https://github.com/tianma-if/leeef-reader/releases/latest)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)
[![爱发电赞助](https://img.shields.io/badge/爱发电-946ce6?style=social&logo=github-sponsors)](https://afdian.com/a/tianma-if)

简体中文 | [English](README.md)

> **Leeef Reader：开源、离线优先、MCP 原生、手机跟手翻页的电子书阅读器。**

Leeef Reader 是一款把书库、进度和笔记留在你自己设备上的电子书应用。导入即可阅读，不需要 Leeef 账号。需要 AI 或 Agent 时，用你自己的接口；也可以在设置里启动 MCP，让 Claude Code、Codex 等工具直接查询应用正在使用的那份 SQLite 书库。

> 💡 **书在你的设备上**
> Leeef 不强制云账号，也不提供 Leeef 云。书籍、书架、书摘和进度保存在本地 `leeef.sqlite`，你可以自己打开查看。对象存储和 AI 凭据由你提供，只在桌面端填写。

> ⭐ 如果 Leeef Reader 对你有帮助，欢迎点个 Star。你的支持会让更多人找到一款不必挂在网店账号后面的阅读器。

## 为什么做 Leeef

很多人硬盘里已经有一堆 EPUB、PDF 和中文 TXT。常见方案总会拿走一部分控制权：

- **Kindle 等商店阅读器**：好用，但书库、划线和文件往往在别人的目录里，导出是事后补丁。
- **Apple Books**：困在一家公司的设备里。没有 MCP，不能自带模型，Agent 也进不去书架。
- **商业阅读 App**：信息流、排行和广告跟书抢注意力，你的文件不是产品本身。
- **不少开源阅读器**：桌面格式支持很好，手机翻页缺少跟手的书页感，也很少让 AI Agent 和阅读器共用同一套书库协议。

**Leeef 补的就是这块**：系统 WebView 里排版，手机 captured-slide 跟手翻页；MCP 和应用内 AI 都对着同一份 SQLite；不强制注册。

> 💡 **一种好用的用法：**
> 书库放在电脑上，需要对话时填写 OpenAI 兼容接口；需要 Agent 时启动 MCP，让它搜书、搜书摘、看进度。手机上导入和阅读即可；密钥不在手机设置里填，之后通过配对带过来。

## 截图

<p align="center">
  <img src="store-assets/screenshots/android/01-library-zh-CN.jpg" alt="Leeef 书库：书架、标签与封面" width="220" />
  &nbsp;
  <img src="store-assets/screenshots/android/02-reader-zh-CN.jpg" alt="Leeef 分页阅读界面" width="220" />
  &nbsp;
  <img src="store-assets/screenshots/android/03-notes-zh-CN.jpg" alt="Leeef 笔记：书摘与书签" width="220" />
</p>

## 客户端下载

当前 GitHub Release 提供 **已签名** 的 macOS 与 Android 安装包。Google Play 使用同一 Android 包名。

<p>
  <a href="https://github.com/tianma-if/leeef-reader/releases/latest"><img src="assets/readme/platforms/macos.svg" alt="下载 macOS 客户端" width="40" height="40" /></a>&nbsp;&nbsp;
  <a href="https://github.com/tianma-if/leeef-reader/releases/latest"><img src="assets/readme/platforms/android.svg" alt="下载 Android APK" width="40" height="40" /></a>&nbsp;&nbsp;
  <a href="https://play.google.com/store/apps/details?id=dev.leeef.leeef_reader"><img src="assets/readme/platforms/google-play.svg" alt="从 Google Play 获取 Leeef Reader" width="40" height="40" /></a>
</p>

- **macOS**：从 [GitHub Releases](https://github.com/tianma-if/leeef-reader/releases/latest) 下载 universal DMG / ZIP（Developer ID 签名并公证）。
- **Android**：GitHub Releases 上的 arm64 APK，或 [Google Play](https://play.google.com/store/apps/details?id=dev.leeef.leeef_reader) 的 Play App Signing AAB。
- **iOS 与 Windows** 安装包不在当前 Release 中，列在路线图里，本文不把它们写成已交付。

旧版 Flutter 客户端不会自动升级到此应用，书库也不会自动迁移。

## 功能

- **离线优先书库**：导入 EPUB、PDF、TXT、MOBI、AZW3 与 FB2。无需 Leeef 账号，无广告，无跨应用追踪。
- **打得开的中文 TXT**：UTF-8，以及无 BOM 的 GBK / GB18030；去掉非法 XML 字符；有「第×章」时按章节切开。
- **书架与标签**：多层书架、标签、搜索，未读 / 在读 / 读完筛选，以及元数据编辑。
- **系统 WebView 分页**：用仓库内 vendored 的 [foliate-js](https://github.com/johnfactotum/foliate-js) 在同一块 WebView 里排版，不是远程网页。
- **手机跟手滑动翻页**：分页模式下只截当前页，底下阅读面瞬间跳栏，overlay 跟手滑走。截图失败则退回普通下一页 / 上一页。桌面分页使用 foliate 动画；两端都可改连续滚动。
- **能长期用的阅读外观**：字号、行距、单栏 / 双栏，纸张 / 护眼 / 夜间，简体 / 繁体转换。
- **书摘、书签与笔记**：划线和书签跟着书走；笔记页可按书籍、类型和颜色筛选。
- **阅读统计**：阅读时长、阅读天数、读完的书，以及各书阅读时长排行。
- **OPDS 目录**：浏览并下载你配置的 OPDS 源。
- **自带 AI 接口**：桌面设置填写 OpenAI 兼容 Endpoint、API Key 和模型（OpenAI、DeepSeek、OpenRouter、xAI 等）。对话在进程内流式输出。模型可查询本地书库；改书库的操作会先请你确认。
- **进程内 MCP**：在设置里启动书库 MCP。它在本机 loopback 上提供 HTTP，读写的就是阅读器正在用的 `leeef.sqlite`。Agent 可以列书、抽正文、搜书摘，并在确认后写入。
- **桌面填凭据，手机配对**：对象存储、AI 等密钥只在电脑上填写。手机展示配对码，而不是这些表单。
- **可打开的本地数据**：书库是标准 SQLite。核心写入会在同一事务里记下 `sync_operation`，以后接到你自己的云时有日志，而不是旁路改表。

## MCP

Leeef 在 Tauri 进程内提供 [Model Context Protocol](https://modelcontextprotocol.io/)。在设置里启动 MCP，把打印出的本机 loopback 地址和 Bearer token 交给 Agent。

读工具包括 `list_books`、`search_books`、`get_book`、`get_book_content`，以及书架、书摘、书签和阅读进度。写操作会返回一份 plan，必须再走 `confirm_write` → `apply_write`，Agent 不能一笔直接改库。

> 💡 **和 Agent 一起用：**
> 问上周在读什么、按主题抽出书摘，或让 Agent 在你确认后把一本书放进某个书架。MCP 走的就是阅读器同一套 `db.rs`，不是另开一份 SQLite。

## 数据、AI 与同步

- 书籍和阅读数据默认只在本机。
- AI 可选，接口和密钥由你提供，不必离开你输入它们的那台电脑。
- 跨设备的目标模型是：**你自己的** S3 兼容存储或 WebDAV，再加上局域网配对，让手机拿到配置而不用手打密钥。配对与对象存储引擎仍在迁到当前 Tauri 客户端；设置项和 `sync_operations` 已经在。协议见 [trusted-device-sync.md](docs/trusted-device-sync.md)。

在线功能需要网络，以及你自行提供的第三方凭据。应用内不出售 AI 或云存储。

## 开发中（尚未发布）

当前工作区新增加密 S3/WebDAV 书库同步、密码保护的书库备份，以及选中文字后的 AI 阅读助手。书库同步需主动开启，现有用户默认仍只同步配置。功能范围、限制与验证情况见[开发与验收记录](docs/reader-improvements.md)。

## 路线图

以下内容不在当前 GitHub Release 中：

- 已签名的 iOS 与 Windows 安装包
- 此客户端上完整的 S3 / WebDAV 同步与二维码配对
- Sparkle（macOS）与 Play 自动更新

## 技术栈

- **应用**：Tauri 2、Vite、React、TypeScript。壳层用 Tailwind CSS 与 shadcn/ui；阅读表面保持自绘（foliate + captured slide）。
- **阅读**：系统 WebView 中 vendored 的 foliate-js。TXT 先转成 EPUB，再进同一分页器。
- **原生**：`apps/reader/src-tauri`（Rust、rusqlite）。Android `PixelCopy` / iOS 截图在 `native-bridge` 插件里。
- **MCP**：官方 Rust SDK（`rmcp`）跑在 `apps/reader/src-tauri` 里，本机 Streamable HTTP 加 Bearer token。
- **标识**：`dev.leeef.leeef-reader`（Android applicationId 为 `dev.leeef.leeef_reader`）。

## 快速开始

```sh
cd apps/reader
npm install
npm run tauri dev
```

MCP 测试：

```sh
cd apps/reader/src-tauri
cargo test --lib
```

Android 调试构建只使用 **USB 真机**，不要开模拟器。说明见 [docs/tauri-reader.md](docs/tauri-reader.md)。

## 目录结构

```text
apps/reader                 Tauri 2 + Vite + React 客户端
apps/reader/public/vendor/foliate-js
                            vendored 分页器，EPUB/MOBI/FB2/PDF
apps/reader/src-tauri       Rust 宿主、rusqlite、进程内 MCP
apps/reader/src-tauri/plugins/native-bridge
                            翻页截图与原生选文件
docs                        阅读壳与配对说明
store-assets                商店文案、隐私与截图
assets/brand                Logo 与标识
.github/workflows           CI 与签名 GitHub Release
```

## 社区与反馈

- Bug 与功能建议：[GitHub Issues](https://github.com/tianma-if/leeef-reader/issues)
- 发布包：[GitHub Releases](https://github.com/tianma-if/leeef-reader/releases)
- 隐私：[隐私政策](store-assets/privacy-policy.zh-CN.md)

## 致谢

- EPUB 分页与格式适配使用 [foliate-js](https://github.com/johnfactotum/foliate-js)，源码 vendored 在本仓库。
- 应用壳层使用 [shadcn/ui](https://ui.shadcn.com/) 与 [Tauri](https://tauri.app/)。
- 移动端滑动翻页依据当代 WebView 阅读器的公开交互独立实现（只截当前页、底下瞬间跳栏、overlay 跟手滑动）。

## 商标与品牌使用

Leeef Reader 名称、Logo 及其他品牌标识用于识别官方项目。Fork 或修改版可以说明其「基于 Leeef Reader」，但不得暗示官方身份或误导用户。开源许可不授予商标权利；其他使用须事先取得项目维护者的书面许可。

## 免责声明

Leeef Reader 是一款完全独立的开源软件，与 Amazon、Apple、Google 或任何电子书商店不存在授权、赞助或隶属关系。

Leeef 不托管你的书库。你导入的内容由你负责。可选的第三方 AI、TTS、OPDS 与对象存储服务由对应提供商运营，适用其自身条款。

## License

[AGPL-3.0](LICENSE)
