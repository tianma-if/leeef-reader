# 翻页性能与回归（2026-09-22）

本次调整覆盖 `ReaderView`、captured slide 调度和 Android native bridge，未发布正式版本。

## 自动验证

- `npm test`：14 个文件、53 项测试通过。新增覆盖连续输入合并、退出时清空队列、失败恢复、截图失败降级、原生动画期间互斥、拖动 IPC 合并、取消后恢复、书末边界、迟到截图清理、iOS 透明滑动层与缓存失效。
- `npm run build`：通过。
- `cargo test --lib`：24 项通过。
- `tauri android build --debug --apk --target aarch64 --ci`：通过，调试包 applicationId 为 `dev.leeef.leeef_reader.debug`。

## USB 真机

设备为 Rakuten BIG plus（3917JR）、Android 10。仅使用 USB 真机，未使用模拟器。安装并运行 debug 构建；已有阅读数据保留。

- 两轮每轮前翻 8 次、后翻 8 次，单次点击间隔约 0.8 秒加 adb 调用耗时，回到相同书页。
- 长距离左滑提交、右滑返回：可见段落恢复一致。
- 短距离慢滑取消：可见段落与手势前一致，无残留遮挡。

`gfxinfo` 第二轮（页面稳定后，16 次点击）记录：320 帧，31 个 janky frames（9.69%），P50 5ms、P90 13ms、P95 31ms、P99 36ms，High input latency 12。首轮为 320 帧、31 个 janky frames，P90 14ms、P95 28ms、P99 36ms。

此前手机已安装调试包的参考采样为 516 帧、52 个 janky frames（10.08%），High input latency 57。**旧包的源码版本未锁定，且采样帧数不同，不能据此宣称严格的前后性能提升比例。** 当前仍有截图/纹理上传阶段的长帧，以上是单台设备 debug 构建的窗口帧统计，不代表所有机型、WebView 内容帧或端到端响应时延。

本地原始记录在 `/tmp/leeef-page-turn-qa/`：`before-gfxinfo.txt`、`after-gfxinfo.txt`、`stable-gfxinfo.txt`，以及 `swipe-forward.xml`、`swipe-back.xml`、`swipe-cancel.xml`。这些临时文件未提交到仓库。

## 浏览器与平台边界

Chrome 使用实际 ReaderView、foliate 引擎和本地生成的三章 EPUB，存储接口使用 Tauri mock：快速连按五次完成当前页与一个最新后续请求；随后可反向翻页，并连续跨越三章到达书末。浏览器验证不能代替移动端截图桥接验证。

iOS 没有进行真机验证；取消固定等待和透明容器由自动测试覆盖，仍需在 WKWebView 真机上检查首帧和跨章表现。macOS 原生 WebView 未单独验收。

Android 就绪判断采用官方 [WebView.VisualStateCallback](https://developer.android.com/reference/android/webkit/WebView.VisualStateCallback)，回调表示视觉状态可在下一次绘制中呈现；实现额外等待绘制帧，并保留 800ms 超时回退。
