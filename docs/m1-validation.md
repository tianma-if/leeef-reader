# M1 P0 纵向闭环验证记录

更新日期：2026-08-22

## 当前结论

| 验收项 | 状态 | 可运行闭环 |
| --- | --- | --- |
| 导入 → 阅读 → 摘录 → 同步 | 通过 | EPUB、PDF、TXT 均完成导入、基础阅读与导航、稳定定位与进度恢复、书摘/书签，以及跨设备文件同步与完整性恢复验证 |
| MCP 查询与确认写入 | 通过 | `list_books` 查询；`plan_create_excerpt → confirm_write → apply_write` 一次性确认链；书摘、同步操作和审计事件在同一 SQLite 事务提交 |
| 移动端 Page Curl 与降级 | 通过 | iOS/Android 阅读页使用独立 foliate WebView 预渲染当前与相邻页纹理并交给 Fragment Shader；截图或 Shader 不可用时自动执行普通翻页 |
| 四端完整性与恢复 | 通过 | macOS、iPhone 真机、Android 16 ARM 模拟器和 Windows WebView2 均运行阅读集成与 M1 数据纵向测试；离线操作保留、幂等重放、冲突合并、损坏 blob 拒绝和修复重试均通过 |

M1 的 P0 格式纵向闭环已经完成。EPUB、PDF 与 TXT 三种首发必选格式均通过导入、阅读、定位恢复、书摘/书签、同步与四端自动化验证。当前同步产品入口使用 `DirectorySyncBackend`，可指向共享目录或网络盘，并严格采用与对象存储一致的 `blobs/{sha256}` 与 `ops/{deviceId}` 布局。

## 关键实现

- `BookImportService`：流式 SHA-256、格式白名单、受管目录原子落盘、重复导入和损坏副本修复。
- `ReaderScreen`：按 EPUB、PDF、TXT 分派阅读器；恢复阅读位置、自动保存、目录、书签、文本选择书摘，以及移动端 EPUB Page Curl/普通翻页降级。
- `PdfReaderScreen`：基于 `pdfrx` / PDFium 的页面渲染、目录与页码导航，以 `pdf:<page>` 定位并恢复进度。
- `TxtReaderScreen`：UTF-8/UTF-16/UTF-32/GBK 解码、自动章节识别与分页，以 `txt:<offset>` 稳定定位并恢复进度。
- `LibraryRepository`：图书、元数据、进度、书摘和书签的唯一写入路径；业务数据和 `sync_operations` 同事务提交。
- `SyncEngine`：先上传本地待处理操作，再幂等应用远端操作，最后按内容哈希下载缺失书籍。
- `DirectorySyncBackend`：不可变 blob/operation 布局、原子写入、SHA-256 完整性验证和安全存储键。
- `leeef-mcp`：loopback + Bearer 鉴权、只读查询、五分钟写计划、一次性确认令牌、事务写入和审计。

## 已执行验证

```text
flutter analyze
  No issues found

flutter test
  41 项全部通过

go test ./...
  查询、鉴权、plan → confirm → apply、事务写入与审计全部通过

flutter test integration_test/foliate_reader_test.dart -d macos
flutter test integration_test/m1_vertical_slice_test.dart -d macos
flutter test integration_test/required_formats_test.dart -d macos
  EPUB 阅读 3 项 + M1 数据纵向闭环 1 项 + PDF/TXT 阅读恢复 2 项通过

flutter test integration_test/foliate_reader_test.dart -d <iPhone device>
flutter test integration_test/m1_vertical_slice_test.dart -d <iPhone device>
flutter test integration_test/required_formats_test.dart -d <iPhone device>
  iPhone 真机 EPUB 阅读、Page Curl、相邻页纹理、PDF/TXT 阅读恢复与数据同步闭环通过

flutter test integration_test/foliate_reader_test.dart -d emulator-5554
flutter test integration_test/m1_vertical_slice_test.dart -d emulator-5554
flutter test integration_test/required_formats_test.dart -d emulator-5554
  Android 16 ARM EPUB 阅读、Page Curl、相邻页纹理、PDF/TXT 阅读恢复与数据同步闭环通过

GitHub Actions Leeef Windows verification #32555455117
  Windows WebView2 EPUB 阅读、PDFium PDF 阅读、TXT 阅读、41 项 Flutter 测试、Go/MCP 和 M1 数据纵向测试通过
```

Windows CI：[Leeef Windows verification #32555455117](https://github.com/tianma-if/leeef-reader/actions/runs/32555455117)

## 故障恢复覆盖

- 后端离线或上传失败时不标记本地操作，下一次同步继续重试。
- 已应用 operation ID 重放不会产生重复实体。
- 同时间冲突使用 operation ID 做确定性决胜，旧写入不能复活较新的删除标记。
- 下载书籍前后校验 SHA-256；损坏文件不会挂接到书库，远端恢复后可再次同步。
- MCP 未确认、令牌错误、过期或重复应用均拒绝写入。
- MCP 成功写入同时生成待同步操作和审计事件，不绕过操作日志协议。
