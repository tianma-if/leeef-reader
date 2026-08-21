<div align="center">

# 🍃 Leeef Reader

**跨端同步、MCP 原生、支持 3D 翻页的电子书阅读器。**

iOS · Android · macOS · Windows

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Status: Early Development](https://img.shields.io/badge/Status-Early_Development-orange.svg)](#项目状态)

</div>

## 核心能力

### 1. 跨端同步

以下数据在 iOS、Android、macOS 和 Windows 之间保持一致：

| 数据 | 同步内容 |
| --- | --- |
| 书籍文件 | EPUB、PDF、TXT 原文件、封面和元数据 |
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

### 3. 交互式 3D 翻页

3D Page Curl 是核心能力，不是可选装饰：

- 支持拖拽、回弹、甩页和取消
- 支持移动端触控、桌面端鼠标与触控板
- 支持 EPUB、PDF 和 TXT
- 支持单页、双页与横竖屏布局
- 翻页时预渲染相邻页面，避免动画帧内重新排版
- 60fps 为基础目标，高刷新率设备针对 120Hz 优化

翻页引擎采用页面纹理与 Fragment Shader 实现，不依赖通用翻页 Widget。

## 技术架构

```text
┌────────────────────────── Flutter App ──────────────────────────┐
│                                                                 │
│  EPUB.js/WebView     pdfrx/PDFium       TXT Layout              │
│          └──────────────┬────────────────┘                       │
│                         ▼                                       │
│                Unified Page Model                               │
│          页面纹理 · 文本范围 · 原文定位 · 命中区域               │
│                         │                                       │
│                         ▼                                       │
│                  PageCurlEngine                                 │
│                                                                 │
│  Riverpod ───── Drift/SQLite/FTS5 ───── Sync Engine             │
│                              │                 │                │
└──────────────────────────────┼─────────────────┼────────────────┘
                               │                 │
                               ▼                 ▼
                          leeef-mcp          S3 Storage
```

## 技术选型

| 模块 | 方案 |
| --- | --- |
| 跨端框架 | Flutter / Dart |
| 状态管理 | `flutter_riverpod` |
| 本地数据库 | `drift` + `drift_flutter` + SQLite FTS5 |
| EPUB 排版 | `epub.js` + `flutter_inappwebview` |
| EPUB 解包 | `archive` |
| PDF | `pdfrx` / PDFium |
| 3D 翻页 | 自研 `PageCurlEngine` + Flutter Fragment Shader |
| 页面快照 | PDF bitmap、`RepaintBoundary`、原生 WebView Snapshot Adapter |
| 同步存储 | S3 兼容对象存储 |
| S3 签名 | `aws_common` + `aws_signature_v4` |
| 凭证存储 | `flutter_secure_storage` |
| MCP Server | Go + 官方 MCP Go SDK，编译为桌面端单文件 sidecar |
| MCP Client | Dart + `dio`，支持 Streamable HTTP |

## 同步设计

S3 中的数据按以下方式组织：

```text
books/{sha256}/original.epub       书籍原文件
books/{sha256}/cover               封面
ops/{deviceId}/{ulid}.json         增量操作
checkpoints/{deviceId}.json        同步水位
```

同步引擎负责：

- 幂等应用操作
- 多设备冲突检测与合并
- 删除标记和恢复
- ETag 条件写入
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

## 开发路线图

### Phase 1：阅读内核与 3D 翻页

- [ ] Flutter 四端工程骨架
- [ ] EPUB、PDF、TXT 导入与阅读
- [ ] 统一页面模型
- [ ] 3D Page Curl 手势、Shader 和页面缓存
- [ ] 阅读进度、书摘、书签和书架目录本地存储

### Phase 2：跨端同步

- [ ] 书籍文件同步
- [ ] 阅读进度同步
- [ ] 书摘和书签同步
- [ ] 书架目录同步
- [ ] 冲突、离线恢复和多设备自动化测试

### Phase 3：MCP 管理

- [ ] `leeef-mcp` 桌面 sidecar
- [ ] 书籍、书摘、书签、书架目录 Resources
- [ ] 完整查询与管理 Tools
- [ ] 写操作确认、权限和审计日志
- [ ] MCP 修改结果自动同步到其他设备

### Phase 4：平台完善

- [ ] iOS / Android 触控、后台和功耗优化
- [ ] macOS / Windows 键盘、窗口和触控板优化
- [ ] 性能基准、数据迁移和故障恢复

## 项目状态

项目处于早期开发阶段，当前优先级依次为：

1. 阅读内核和 3D 翻页
2. 五类数据的跨端同步
3. MCP 全量读写管理

## 许可证

本项目采用 [Apache License 2.0](LICENSE) 开源。
