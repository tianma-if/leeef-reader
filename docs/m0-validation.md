# M0 技术验证记录

更新日期：2026-08-22

## 当前结论

| 验证项 | 状态 | 已验证 | 尚未完成 |
| --- | --- | --- | --- |
| foliate-js | 进行中 | macOS 原生 WebView、iPhone 真机、Android 16 ARM 模拟器均通过 EPUB 元数据、目录、分页排版参数与实际正文、跳转 CFI 和文本选择 CFI 集成测试 | Windows WebView2 实机/CI 验证 |
| Page Curl | 通过 | iPhone 真机与 Android 16 ARM 模拟器均成功运行 Fragment Shader，并从独立 foliate WebView 抓取两张相邻页纹理；iPhone profile build/raster p90 为 0.757/0.010ms，Android 宿主 GPU profile 为 1.002/2.171ms，均满足 120Hz 预算 | 发布前继续在多档 Android 真机做兼容性与视觉调优 |
| Drift/同步 | 通过 | SQLite v2 schema、事务式操作日志、SHA-256 去重、进度设备历史、删除标记、幂等与双设备乱序收敛；日志失败会回滚业务写入 | M1 再加入真实 S3 双客户端故障注入 |
| MCP sidecar | 通过 | Go sidecar 使用官方 MCP Go SDK v1.7.0；Bearer 鉴权、随机 loopback 端口、Flutter 进程拉起、MCP 初始化以及只读 Drift `library_stats` 调用均通过 | 扩展完整 Resources/Tools 和 `plan → confirm → apply` 写操作 |

M0 尚不能整体关闭：Windows foliate-js 实际运行验证仍是硬性缺口。Windows workflow 已就绪，推送分支后可在 `windows-latest` 执行。

Windows 开发机也可在仓库根目录直接执行：

```powershell
./tool/verify_m0_windows.ps1
```

脚本会验证 NuGet 与 WebView2 Runtime，构建并实际运行 MCP sidecar 测试，然后执行静态分析、全部 Flutter 测试和 Windows WebView2 集成测试。

## 关键实现

- `ReaderContentServer`：随机端口、256-bit 会话令牌、bookId 白名单、HTTP Range、CSP 和路径隔离。
- `FoliateReaderEngine`：统一 ReaderEngine、WebView JavaScript bridge、CFI 定位和文本选择事件。
- `PageCurlSurface`：seek-safe Fragment Shader、手势进度、回弹和甩页完成判定。
- `PageSnapshotCache`：previous/current/next LRU 预取、并发请求去重和 WebView 快照适配。
- `FoliatePageSnapshotView`：独立非交互 WebView，串行定位相邻 CFI 并抓取实际页面纹理。
- Drift schema v2：核心实体、同步操作、审计事件和阅读进度设备历史。
- `leeef-mcp`：官方 Go SDK Streamable HTTP server，随机 loopback 地址和 Bearer token。

## 已执行验证

```text
flutter analyze
  No issues found

flutter test
  25 项全部通过

flutter test integration_test/foliate_reader_test.dart -d macos
  EPUB/CFI/选择通过
  Page Curl Shader 交互通过

flutter test integration_test/foliate_reader_test.dart -d <iPhone device>
  EPUB/CFI/选择通过
  Page Curl Shader 交互通过
  独立 foliate WebView 相邻页纹理抓取通过

flutter test integration_test/foliate_reader_test.dart -d emulator-5554
  Android 16 ARM：EPUB/CFI/选择、Shader 交互、相邻页纹理抓取均通过

flutter drive --profile --no-dds ... -d <iPhone device>
  Page Curl build p90 0.757ms，raster p90 0.010ms，120Hz=true

flutter drive --profile --no-dds ... -d emulator-5554
  Android 16 + Apple M4 Pro 宿主 GPU：build p90 1.002ms，raster p90 2.171ms，120Hz=true
  对照：SwiftShader 软件 GPU raster p90 26.328ms，不作为硬件性能结论

go test ./...
  sidecar 鉴权、health、library_stats 通过
```

## 依赖决策

`flutter_inappwebview` 6.1.5 在当前 Flutter 3.47 / Gradle 9.3 工具链上因旧 `proguard-android.txt` 配置无法构建。M0 暂时固定到 `6.2.0-beta.3`，该版本使用 AGP 8.13.1 和 `proguard-android-optimize.txt`，Android 集成测试已通过。进入发布阶段前必须重新评估稳定版本。

foliate-js 固定在提交 `78914aef4466eb960965702401634c2cb348e9b1`，上游信息与许可证位于 `assets/foliate-js/UPSTREAM.md`。
