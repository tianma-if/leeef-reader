# Tauri 阅读壳（`tauri` 分支）

本分支在当前仓库里另起 Tauri 壳，不 fork Readest，也不另开 GitHub 仓库。Flutter 应用仍在 `main`。

## 布局

- `apps/reader`：Vite + React + Tauri 2
- `apps/reader/public/vendor/foliate-js`：沿用本仓库已 vendored 的 foliate
- `apps/reader/public/reader`：阅读 iframe（和壳同一块系统 WebView）
- `apps/reader/src-tauri/plugins/native-bridge`：Android `PixelCopy` / iOS `takeSnapshot`

## 翻页约定

移动端走 captured slide：只截当前页，底下 iframe 瞬间跳栏，overlay `translate3d`。不要截下一页，不要用框架层去盖 WebView。

TXT 先转 EPUB，再进同一阅读器。

桌面端原生截图尚未接，暂用 foliate 自带的 `animated` 分页。

## 开发

```bash
cd apps/reader
npm install
npm run tauri dev
```

Android / iOS 需先在 `apps/reader` 里执行 `npm run tauri android init` / `ios init`，真机调试，不要用模拟器。
