# M2 / M3 功能兼容与生态验证记录

更新日期：2026-08-30

## 当前结论

M2 与 M3 的功能范围已经落到可操作界面和真实数据链路，不再是占位入口。核心写操作统一经过 `LibraryRepository` 和同步操作日志；AI 与 MCP 写入均保留确认和审计边界。

| 范围 | 已完成能力 | 主要验证 |
| --- | --- | --- |
| 格式与书库 | EPUB、MOBI、AZW3、FB2、TXT、PDF；批量/拖拽/分享导入；元数据与封面；书架、标签、筛选排序、文件替换/释放/下载 | 导入、仓库事务、格式阅读与同步测试 |
| 阅读与样式 | 分页、滑动、无动画、连续滚动、单双栏；目录/搜索/历史；点击区、音量键、键盘、滚轮；全屏/常亮；页眉页脚内容；字体、排版、CSS、日夜背景、电子墨水屏、代码配色、简繁转换 | ReaderPreferences、TXT 定位、foliate WebView 集成、PDF/TXT 渲染测试 |
| 笔记与分享 | 书签、书摘、笔记工作区、批量操作、Markdown/TXT/CSV/章节合并导出；可定制分享卡片和系统分享 | 仓库与导出测试 |
| TTS 与 AI | 系统/OpenAI/Azure/阿里云 TTS；声音和句级控制、睡眠定时、媒体控制；多 Provider AI、API Key 轮换、Prompt、章节/全书上下文、全文翻译、缓存/重试/取消；应用内动态查询书库、书架、标签、书摘、书签、历史与进度，写入 Tools 确认后执行 | TTS、翻译、Provider、Prompt、Tool Registry 测试 |
| 统计 | 时长、天数、连续阅读、完成数、热力图、7/30 日趋势、阶段汇总、随机书摘、继续阅读、卡片增删排序、记录编辑删除撤销 | 阅读会话仓库测试与静态检查 |
| 同步与数据 | S3-compatible、WebDAV、目录后端；前台/后台、Wi-Fi 约束、系统完成通知；局域网一次性配对、可信设备列表、配置与凭据端到端加密同步、撤销密钥轮换；批量云端下载；完整备份恢复；MD5、缺失文件、缓存、字体、日志、代理；书籍/封面/SQLite 一致性数据目录迁移 | S3、WebDAV、SyncEngine、配对、加密配置、密钥轮换、备份、迁移、维护测试 |
| MCP | 全部 README Resources/Tools；`plan → confirm → apply`、权限、operationId 幂等和审计 | Dart 端到端 MCP 桥接与 Go server capability 测试 |
| OPDS 与平台 | 目录管理、鉴权、浏览、搜索、分页、下载导入；中英日界面及二级配置弹窗；响应式导航、窗口恢复、开书动画、震动、更新检查 | OPDS 服务测试、本地化 widget/unit 测试、三端构建 |
| 质量 | Page Curl 按实际屏幕刷新率记录 P90、估算 FPS 和慢帧比例；阅读点击区语义、TTS live region、颜色选择名称/选中/点击语义；跨平台 CI | Page Curl 性能计算测试、Semantics widget 测试、`flutter analyze`、完整测试、CI workflow |

## 本次已执行验证

```text
flutter analyze
  No issues found

flutter test
  137 项全部通过

flutter test integration_test/foliate_reader_test.dart -d macos
  foliate/WebView 与 Page Curl 集成测试 6 项全部通过

go test ./...  （sidecars/leeef-mcp）
  全部通过

flutter build apk --debug
  通过

flutter build ios --debug --no-codesign
  通过

flutter build macos --debug
  通过
```

Windows 无法在 macOS 主机本地构建。Windows 端已接入系统通知，并使用当前用户的计划任务每 30 分钟启动 `--background-sync`；命令生成包含带空格可执行路径的单元测试。`.github/workflows/ci.yml` 已将 `flutter build windows --debug` 设为独立必跑任务，同时在 Linux/macOS runner 验证 Android、iOS 和 macOS；原有 `m0-windows.yml` 继续保留 WebView2 与 MCP 的 Windows 深度验证。Windows 计划任务的实机注册与通知展示仍由 Windows CI/发布验收覆盖。

## 数据迁移与失败边界

- 自定义数据目录先迁移书籍和封面、更新数据库指针，再使用 SQLite `VACUUM INTO` 生成一致性数据库快照。
- 新数据库打开前设置重启标记，重启前后台同步暂停，避免新旧数据库产生两条写入历史。
- 数据库文件及 WAL/SHM 文件不会被孤立缓存清理误删。
- 备份恢复先校验清单与 SHA-256，再替换业务表和受管文件；失败时保留原库。
- 后台同步只在已启用、网络满足约束且没有待重启数据库迁移时运行。
- 可迁移配置和安全存储凭据离开设备前使用 AES-256-GCM 加密；配对使用 X25519 + HKDF-SHA256 建立会话密钥。
- 撤销设备创建下一密钥 epoch，并只为仍可信设备写入新组密钥信封；并发轮换使用条件写入，避免覆盖。

## 发布门禁

每次主分支或 PR 的相关改动必须通过：

1. Dart 静态检查和完整 Flutter 测试。
2. Go MCP 全量测试。
3. Android debug APK 构建。
4. macOS foliate/Page Curl 集成测试，以及 iOS simulator 与 macOS debug 构建。
5. Windows debug 构建。

设备端 Page Curl 的最终发布验收仍应读取应用日志中的真实设备 P90/慢帧数据，并覆盖至少一台 60Hz 和一台 120Hz iOS/Android 设备。
