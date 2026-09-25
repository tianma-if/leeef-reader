# Tauri 阅读壳（`tauri` 分支）

数据层是 SQLite `leeef.sqlite`。MCP 在 Tauri 进程内用官方 `rmcp` SDK 提供本机 Streamable HTTP，读写走同一套 `db.rs`。设置里启动后会给出 loopback endpoint 和 Bearer token。

本仓库主线是 Tauri 壳，不 fork Readest，也不另开 GitHub 仓库。

## 布局

- `apps/reader`：Vite + React + Tailwind + shadcn/ui + Tauri 2（壳用组件库，阅读表面仍自绘）
- `apps/reader/public/vendor/foliate-js`：沿用本仓库已 vendored 的 foliate
- `apps/reader/public/reader`：阅读 iframe（和壳同一块系统 WebView）
- `apps/reader/src-tauri/plugins/native-bridge`：Android `PixelCopy` / iOS `takeSnapshot`

## 翻页约定

移动端走 captured slide：只截当前页，底下 iframe 瞬间跳栏，overlay `translate3d`。不要截下一页，不要用框架层去盖 WebView。

TXT 先转 EPUB，再进同一阅读器。

移动端分页阅读：foliate `no-swipe` + 窗口 `PixelCopy` 只截当前页，底下瞬间跳栏。桌面暂用 foliate `animated`。

翻页请求串行执行，动画中最多保留一个最新的后续请求，避免连按打断动画或积压翻页。移动端完整收尾时长为 280ms，按剩余距离缩短，最低 90ms。

- Android 的原生 cover 直接持有截图，不再编码 JPEG / base64 回传；拖动位置按帧合并且最多一个 IPC 在途，收尾用原生动画一次完成。跳页后通过 WebView visual-state callback 等待绘制，不再用截图颜色猜测页面是否就绪。
- iOS 使用透明容器上的截图滑动层，让新页面随滑动露出；排版完成后等待绘制帧，移除固定的 420ms 等待。画布保持原生截图分辨率，避免把 2x 截图放大为 3x 纹理。
- 取消手势时在遮挡下恢复原页并等待绘制；书首/书末未发生导航时不执行反向补偿。预截图遇到页面失效或退出阅读器会丢弃。

验证记录见 [翻页性能与回归](page-turn-performance.md)。

## 开发

```bash
cd apps/reader
bun install
bun run tauri dev
```

## Android 真机

只使用 USB 真机，不要开模拟器。Redmi / HyperOS 需打开开发者选项里的 **USB 安装**，`adb install` 弹出「USB安装提示」时点 **继续安装**。

```bash
cd apps/reader
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/28.2.13676358"
bun run tauri android build --debug --apk --target aarch64 --ci
adb -s fb091b3c install -r -t src-tauri/gen/android/app/build/outputs/apk/universal/debug/app-universal-debug.apk
adb -s fb091b3c shell am start -n dev.leeef.leeef_reader/.MainActivity
```

调试包 applicationId 为 `dev.leeef.leeef_reader.debug`（见 `debug-id.gradle.kts`），避免覆盖商店版。若某次构建尚未套上 suffix，安装的是 `dev.leeef.leeef_reader`。

## iOS

App Store 继续使用既有 bundle id `dev.leeef.leeefReader`（见 `src-tauri/tauri.ios.conf.json`），不要改成桌面用的 `dev.leeef.leeef-reader`。Xcode 工程在 `src-tauri/gen/apple/`，与 Android 一样提交进仓库。

```bash
cd apps/reader
# Xcode 27 需要 llvm-objcopy，否则 @_cdecl 符号会内化，链接失败。
rustup component add llvm-tools
bun run tauri ios init --ci   # 仅在需要重新生成 Xcode 工程时
bun run tauri ios build --ci --export-method app-store-connect
```

正式发版由 `.github/workflows/tauri-release.yml` 的 iOS job 签名并上传到 App Store Connect。`CFBundleVersion` 默认按 `major * 1000000 + minor * 1000 + patch` 计算，必须高于 Flutter 时代最后一次的 `25`。重新上传同一版本时用 `ios_build_number` 覆盖。上传成功不等于审核通过或商店上架。
