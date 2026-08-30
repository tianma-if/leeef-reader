# AGENTS.md

本文件约束参与 Leeef Reader 开发与发布的 AI 代理和协作者。技术栈、产品范围与平台状态优先参考 `README.md`，具体凭据和操作步骤参考 `docs/releasing.md`。

## GitHub Actions 与 Release 规则

1. **Fork 工作流边界**：仅官方仓库需要的签名、商店交付、GitHub Release 资产上传和发布审计 Job，必须使用 `github.repository == 'tianma-if/leeef-reader'` 的 Job 级门禁，避免下游 Fork 分配 Runner 或尝试访问官方 Environment。
2. **版本格式与递增**：正式 Tag 和 GitHub Release 标题使用 `vX.Y.Z`，不得使用 Draft 或 Prerelease 作为最终状态。发版必须显式选择 SemVer 的 `patch`、`minor` 或 `major`，禁止为了维持发版节奏把用户可感知的新能力或新平台压成 patch。`pubspec.yaml` 使用 `X.Y.Z+N`：`X.Y.Z` 必须与 Tag 一致，构建号 `N` 必须严格递增，并同时作为 Android `versionCode` 与 Apple build number。
3. **发布基线**：以上一个正式 Release 为审计基线。Release 说明必须覆盖该基线后的全部用户可感知变化；纯测试、重构、CI 或文档提交可不进入公开说明，但必须在发布审计记录中给出明确理由。
4. **平台范围**：不得在 Release 中宣称尚未交付或未经验证的平台。Android 以 Google Play 轨道中的 Play App Signing 构建为准，iOS 以 App Store Connect/TestFlight 构建为准，macOS 以签名、公证且带 Sparkle 更新元数据的 universal DMG/ZIP 为准。Windows 在正式安装包、签名/更新与审计工作流完成前，不得列为该 Release 的已交付资产。
5. **验证命令**：正式发布前必须通过 `flutter pub get`、`flutter analyze`、`flutter test`、MCP sidecar 的 `go test ./...`，以及 `.github/workflows/ci.yml` 中 Android、iOS、macOS、Windows 的构建门禁。涉及阅读器、导入、同步、后台音频或更新时，还必须完成 `docs/releasing.md` 中对应的真机回归。
6. **Draft 内准备资产**：先创建 `vX.Y.Z` Draft Release，再通过带 `release_tag` 的手动工作流构建、签名、公证并上传资产。资产审计通过后才可公开。`published` 事件只允许审计已有资产，禁止在 Release 已公开后才首次构建或上传正式资产。
7. **签名边界**：签名证书、密钥库、API Key、Sparkle Ed25519 私钥及密码必须保存在仓库外或受保护的 GitHub Environment 中，严禁提交到 Git。Android 正式交付必须启用 Play App Signing；macOS 更新 ZIP 和 `appcast.xml` 必须使用与客户端内置公钥匹配的固定私钥签名。
8. **失败处理**：任一阻塞验证、签名、公证、上传或资产审计失败时，Release 必须保持或恢复为 Draft；修复并重新执行门禁后才可公开。不得发布已知损坏、缺少声明资产或版本不一致的 Release。
9. **商店交付**：Google Play 先使用 `internal` + `draft`，iOS 先上传 TestFlight；真机验证通过后再批准 production 或提交 App Store 审核。商店上传不等于正式上架，商店状态必须单独核验。
10. **发布后行为**：发布流程默认不得下载、覆盖安装或启动开发者机器上的现有应用。已安装的 macOS 客户端通过 Sparkle 更新，Android 客户端通过 Google Play 更新；只有用户明确要求时才执行本机安装验收。
11. **Release 说明**：公开说明使用中英文双语，只写用户可感知的变化、影响和必要的升级提醒。类型检查、构建命令、签名、公证、资产复用等技术验证细节留在 Actions 或关联 Issue，不写入公开正文。推荐结构：

```md
## 🇨🇳 中文说明 / Chinese Changelog

## 主要更新

- 面向用户说明本次变化及影响。

关联 Issue：#<issue-number>

## Key Changes

- Summarize the user-visible change and its impact.

Related Issue: #<issue-number>
```

## 标准发布入口

- 使用 `dart run tool/release.dart` 进行版本规划和提交覆盖审计；该命令默认只执行 dry run。
- 只有在确认计划后才可显式传入 `--execute`。执行模式复用当前源码提交已经通过的跨平台 CI；不存在时只补跑一次。版本号提交使用 `[skip ci]`，避免对同一份源码重复执行门禁。
- 执行模式只准备 Draft Release 和一次 macOS 资产工作流，不会自动公开 Release 或批准商店生产交付。Release 的 `published` 事件只做快速资产审计，不允许重建或覆盖已公开资产。
- 禁止绕过工具的提交覆盖审计直接生成公开说明；遇到工具无法表达的特殊发布场景，应先补充工具及测试，再继续发布。
