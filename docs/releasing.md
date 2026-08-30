# 商店与 macOS 发布

Leeef Reader 使用三个相互独立的手动 GitHub Actions 工作流。首次发布前，应先在 Apple Developer、App Store Connect 和 Google Play Console 创建应用；已登记的标识不可随意更换。仓库级发布约束见 [`AGENTS.md`](../AGENTS.md)，本页说明实际操作。

## 正式 Release 规则

- 正式 Tag 与 Release 标题使用 `vX.Y.Z`；`pubspec.yaml` 必须使用匹配的 `X.Y.Z+N`，其中 `N` 严格递增。
- 必须按 SemVer 显式决定 patch、minor 或 major。用户可感知的新能力和新增平台不能仅因发版方便而归入 patch。
- 以上一个正式 Release 为基线审计变更，并使用中英文说明公开的用户可感知变化；构建、签名和公证细节留在 Actions 或关联 Issue。
- 先创建 Draft Release，在 Draft 内准备并核验 macOS 资产，然后才公开。Release 的 `published` 事件只审计已有资产；审计失败会尝试把 Release 恢复为 Draft。
- Android 与 iOS 是独立的商店交付：先送入 Play internal draft 与 TestFlight，完成真机回归后再进入正式轨道或审核。
- 当前没有正式 Windows 安装包、签名和更新资产工作流，因此不得在 Release 说明中把 Windows 写成该版本已经交付的平台。

## 标准发布命令

发布规划器借鉴 EdgeEver 的显式版本升级、提交覆盖审计、双语变化映射和 Draft 准备边界。它默认只读，不会修改工作区、提交、Tag 或 GitHub 状态：

```bash
dart run tool/release.dart \
  --bump minor \
  --issue-title "Release Leeef Reader 1.1" \
  --label enhancement \
  --change-zh "新增面向用户的能力。" \
  --change-en "Add a new user-facing capability." \
  --change-commit "abcdef1"
```

多项变化按顺序重复 `--change-zh`、`--change-en` 和 `--change-commit`；一项变化可关联逗号分隔的多个提交。上一个正式 Release 之后的每个提交都必须被覆盖。不面向用户的提交使用带具体原因的显式排除：

```bash
--ignore-commit "1234567:仅调整 CI，不影响用户"
```

确认 dry run 输出的版本、构建号、提交覆盖和说明后，使用完全相同的参数并增加 `--execute`。执行模式会确认 `main` 与 `origin/main` 一致，并复用该提交已经通过的跨平台 CI（不存在时只补跑一次）；随后创建跟踪 Issue、更新并提交 `pubspec.yaml`、推送正式 Tag、创建 Draft Release，并触发一次 macOS 资产工作流。仅修改版本号的发版提交带 `[skip ci]`，不会把同一套门禁再跑一遍。它不会公开 Release，也不会批准 Google Play production 或 App Store 审核。

发布规划器自身的回归测试：

```bash
flutter test test/release_tool_test.dart
```

| 平台 | 应用标识 | 工作流 | 产物/目标 |
| --- | --- | --- | --- |
| Android | `dev.leeef.leeef_reader` | `Publish Google Play` | 签名 AAB、Play internal/alpha/beta/production |
| iOS | `dev.leeef.leeefReader` | `Publish iOS App Store` | IPA、App Store Connect/TestFlight |
| iOS 分享扩展 | `dev.leeef.leeefReader.ShareExtension` | 同上 | 随主应用嵌入 |
| macOS | `dev.leeef.leeefReader` | `Build macOS DMG` | x86_64 + arm64 universal DMG |

Apple Team ID 当前为 `9KA3NM38B6`，App Group 为 `group.dev.leeef.leeefReader`。iOS 的两个 App Store provisioning profile 都必须启用这个 App Group。

## Google Play

在 GitHub 创建受保护的 `google-play` Environment，并配置：

- `ANDROID_KEYSTORE_BASE64`：上传密钥库的单行 base64。
- `ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`。
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`：有对应应用发布权限的服务账号 JSON。

首次 AAB 通常需在 Play Console 手工创建应用并上传；随后工作流才能通过 API 更新轨道。建议先选择 `internal` + `draft`，审核确认后再使用 `completed`。每次上传前必须递增 `pubspec.yaml` 中 `version` 的 build number（`+1` 部分）。Play App Signing 与仓库外保存的 upload key 应同时启用。

本地正式构建时，在 `android/key.properties` 写入：

```properties
storeFile=/absolute/path/to/upload.jks
storePassword=...
keyAlias=...
keyPassword=...
```

然后运行 `flutter build appbundle --release`。该文件和密钥库已被 Git 忽略。

也可以不创建本地文件，改用 `ANDROID_KEYSTORE_PATH`、`ANDROID_KEYSTORE_PASSWORD`、
`ANDROID_KEY_ALIAS` 和 `ANDROID_KEY_PASSWORD` 环境变量；CI 与临时发布机推荐使用这种方式。

正式 Android 包通过 Google Play Flexible Update 更新。应用启动、回到前台以及持续运行期间每 6 小时检查一次；发现新版后先显示说明，用户通过 Google Play 的系统确认后，安装包在后台下载，下载完成时 Leeef Reader 再提示“重启以更新”。Google Play 要求首次下载前由用户确认，应用不能绕过这个系统步骤。

该能力只对从 Google Play 安装、且当前账号有权获取更高 `versionCode` 的构建生效。请通过 internal track 或 Internal App Sharing 使用真机验证：从旧版本启动，接受 Play 更新，等待后台下载完成，再确认重启后版本已升级。直接侧载的 APK 仍可手动查看 GitHub Releases，但不会自行下载安装包。

Leeef Reader 不申请 `android.permission.REQUEST_INSTALL_PACKAGES`。发布工作流会检查合并后的 manifest，防止依赖意外加入 APK 自安装权限；请勿为侧载更新绕过这一约束。

## App Store Connect / TestFlight

在 GitHub 创建受保护的 `app-store` Environment：

- Variables：`APPSTORE_ISSUER_ID`、`APPSTORE_API_KEY_ID`。
- Secrets：`APPSTORE_API_PRIVATE_KEY`（`.p8` 内容）、`APPSTORE_CERTIFICATES_FILE_BASE64`（Apple Distribution `.p12` 的 base64）、`APPSTORE_CERTIFICATES_PASSWORD`。

API Key 至少需要 App Manager 权限。工作流会从 App Store Connect 下载主应用与分享扩展的 profile，使用 `ios/ExportOptions.plist` 导出 IPA。关闭 `upload_testflight` 可只生成 IPA，不上传。上传只会把 build 送入 App Store Connect/TestFlight；商店元数据、隐私问卷、截图、定价和最终提交审核仍在 App Store Connect 完成。

## macOS DMG

本地无签名打包：

```bash
./tool/build_macos_dmg.sh
```

产物位于 `build.noindex/distribution/`，包含应用和 `/Applications` 快捷方式。macOS 开发机应先运行一次 `flutter config --build-dir=build.noindex`，避免 Spotlight 和 LaunchServices 把 Debug/Release 构建误认为额外安装的 Leeef Reader；发布脚本也会自动应用该设置。在 Developer ID Application 证书已经导入钥匙串时，可将 `MACOS_CERTIFICATE_NAME` 设置为证书名称或 SHA-1 指纹完成签名（存在同名证书时推荐使用指纹）；再提供 `APPLE_API_PRIVATE_KEY`、`APPLE_API_KEY_ID`、`APPLE_API_ISSUER_ID` 时，脚本会使用 App Store Connect API Key 提交公证并 staple ticket。

GitHub 的 `macos-distribution` Environment 配置：

- Variables：`APPSTORE_ISSUER_ID`、`APPSTORE_API_KEY_ID`。
- Secrets：`MACOS_CERTIFICATES_FILE_BASE64`、`MACOS_CERTIFICATES_PASSWORD`、`MACOS_CERTIFICATE_NAME`、`APPSTORE_API_PRIVATE_KEY`。
- Sparkle 更新签名 Secret：`MACOS_SPARKLE_PRIVATE_KEY`。内容是 Sparkle Ed25519 私钥种子的单行 base64；对应公钥固定在 `macos/Runner/Info.plist`，丢失后不能为已安装客户端发布可信更新。

手动执行工作流可选择无签名构建用于内部测试。正式发布时，先创建 Draft Release，再以该 Draft 的 Tag 作为 `release_tag` 手动运行工作流；工作流会从 Tag 构建、签名、公证，并向 Draft 附加 DMG、供静默下载的 ZIP 以及签名的 `appcast.xml`。Tag 必须与 `pubspec.yaml` 的版本一致，例如版本 `1.0.0+2` 对应 `v1.0.0`。确认工作流成功且 Draft 中三项资产齐全后才可公开 Release；`published` 事件不会重新构建，只审计已有资产。已安装的 macOS 客户端每 6 小时静默检查并下载，下载完成后才提示用户重启安装；选择稍后时，正常退出应用也会完成安装。

首次配置更新签名时，将仓库外保存的私钥写入 GitHub Environment：

```bash
gh secret set MACOS_SPARKLE_PRIVATE_KEY \
  --repo tianma-if/leeef-reader \
  --env macos-distribution \
  < /path/to/sparkle-private-key
```

私钥必须与 `Info.plist` 的 `SUPublicEDKey` 匹配。不要重新生成或提交私钥；应把它作为发布凭据加密备份。

## 发布检查

1. 确认 `main` 与 `origin/main` 一致且工作区干净；以上一个正式 Release 为基线整理中英文用户变更。
2. 显式选择 SemVer 级别，更新 `pubspec.yaml` 的 `version: X.Y.Z+N`；`N` 必须严格递增。
3. 等待当前源码提交的跨平台 CI 全部通过；该工作流统一执行 Flutter 分析与测试、MCP `go test ./...` 以及 Android、iOS、macOS、Windows 构建。发布规划器会直接复用这一结果，不重复执行同一套门禁。
4. 创建 `vX.Y.Z` Draft Release，使用同一 Tag 手动运行 `Build macOS DMG`，确认 DMG、ZIP、`appcast.xml` 已上传且工作流成功。
5. 先发布 Play internal draft 与 TestFlight，完成真机导入、阅读、分享导入、后台音频和同步回归；Android 还需从旧的 Play 版本验证“确认下载 → 后台下载 → 重启安装”完整流程。
6. 在 Intel 与 Apple Silicon Mac 上验证 DMG 可挂载、拖入 Applications，并运行 `spctl --assess --type execute --verbose "Leeef Reader.app"`；从前一正式版本启动应用，确认新版 ZIP 静默下载后出现“重启以更新”，重启后版本号已更新。
7. 公开 GitHub Release 并确认发布后资产审计通过；最后在受保护 Environment 中批准生产轨道或 App Store 审核提交。
