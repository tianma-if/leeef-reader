# 商店与 macOS 发布

当前正式资产走 [`.github/workflows/tauri-release.yml`](../.github/workflows/tauri-release.yml)：对 Draft Tag 手动调度，构建签名 macOS DMG/ZIP、Android APK/AAB（默认上传 Google Play production）和 iOS IPA（默认上传 App Store Connect、提交审核，并在审核通过后自动发布）。旧的 Flutter 工作流 `google-play.yml` / `ios-app-store.yml` / `macos-dmg.yml` 不得对正式 Tag 发版。

首次发布前，应先在 Apple Developer、App Store Connect 和 Google Play Console 创建应用；已登记的标识不可随意更换。仓库级发布约束见 [`AGENTS.md`](../AGENTS.md)，本页说明实际操作。

## 正式 Release 规则

- 正式 Tag 与 Release 标题使用 `vX.Y.Z`；`pubspec.yaml` 必须使用匹配的 `X.Y.Z+N`，其中 `N` 严格递增。
- 必须按 SemVer 显式决定 patch、minor 或 major。用户可感知的新能力和新增平台不能仅因发版方便而归入 patch。
- 以上一个正式 Release 为基线审计变更，并使用中英文说明公开的用户可感知变化；构建、签名和公证细节留在 Actions 或关联 Issue。
- 先创建 Draft Release，在 Draft 内准备并核验 macOS 资产，资产齐全后立即公开，不得停下来询问确认。Release 的 `published` 事件只审计已有资产；审计失败会尝试把 Release 恢复为 Draft。
- 正式发版默认交付 Google Play production（`completed`），并将 iOS 构建上传 App Store Connect、关联正式版本、提交审核，设置为审核通过后自动发布。internal、draft、TestFlight 测试分发和移动端真机回归均不是项目强制前置条件。平台自身的构建处理、资料与审核要求仍适用。
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

仅有发布流程、测试或文档调整且仍需发版时，使用 `--bump patch --maintenance`，不提供 `--change-*`，并用 `--ignore-commit` 为基线后的每个提交注明排除原因。工具仍执行完整提交覆盖审计；公开说明明确本次无用户可感知的功能变化，不虚构功能更新。

当前 Tauri 发版：确认 `main` 与 `origin/main` 一致并复用已通过的 CI；创建跟踪 Issue、同步 `apps/reader/package.json` 与 `apps/reader/src-tauri/tauri.conf.json` 版本、推送正式 Tag、创建 Draft Release，以该 Tag 调度 `tauri-release.yml`（默认 `platforms: all`、`upload_play: true`、`upload_appstore: true`、`submit_appstore: true`）。macOS 与 Android 资产上传到 Draft 后立即公开 GitHub Release。Google Play production（`completed`）以及 App Store Connect 上传、版本关联和送审由该工作流直接执行，不依赖 `published` 事件，也不走旧的 Flutter Job。Sparkle `appcast.xml` 尚未接到这条流水线。

若 `pubspec.yaml` 已因未公开的 Draft 递增，显式添加 `--pending-draft vX.Y.Z`。
工具会验证该 Draft 的 Tag、构建号与当前版本一致，并且位于上一正式 Release 与当前提交之间；
新版本从该 Draft 继续递增，但变更覆盖仍从上一正式 Release 开始，不能漏掉未公开版本中的用户变化。
旧 Draft、Tag 和资产保持不变。该选项不会跳过 CI 或公开前的资产审计。

发布规划器自身的回归测试：

```bash
flutter test test/release_tool_test.dart
```

| 平台 | 应用标识 | 工作流 | 产物/目标 |
| --- | --- | --- | --- |
| Android | `dev.leeef.leeef_reader` | `Tauri signed release` | 签名 APK/AAB；默认 Play production `completed` |
| iOS | `dev.leeef.leeefReader` | `Tauri signed release` | 签名 IPA；默认上传 App Store Connect、提交审核、审核通过后自动发布 |
| macOS | `dev.leeef.leeef-reader` | `Tauri signed release` | Developer ID 签名并公证的 universal DMG/ZIP |

Apple Team ID 当前为 `9KA3NM38B6`。iOS App Store bundle id 为 `dev.leeef.leeefReader`。Flutter 时代的 Share Extension 与 App Group 未迁到 Tauri，当前 IPA 只签主应用。

## Google Play

在 GitHub 创建受保护的 `google-play` Environment，并配置：

- `ANDROID_KEYSTORE_BASE64`：上传密钥库的单行 base64。
- `ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`。
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`：有对应应用发布权限的服务账号 JSON。

首次 AAB 通常需在 Play Console 手工创建应用并上传；随后工作流才能通过 API 更新轨道。官方仓库公开稳定 GitHub Release 时会自动从该 Release Tag 构建签名 AAB，并以 `production` + `completed` 提交 Google Play；Draft 和 Prerelease 不会触发正式上架。手动运行工作流时仍可选择其他轨道与状态，例如仅在需要测试或保留草稿时使用 `internal` + `draft`，不强制先走测试轨道。每个新构建必须递增 `pubspec.yaml` 中 `version` 的 build number（`+1` 部分）；重试或提升同一已上传构建不需要重新构建或递增版本。Play App Signing 与仓库外保存的 upload key 应同时启用。

`changes_not_sent_for_review` 默认关闭；只有 Play 明确要求人工送审时才开启。若签名 AAB 已成功构建并保留为 Actions artifact，但商店提交失败，可在最新工作流上设置 `artifact_run_id` 和 `release_tag` 重试上传：工作流会校验原始运行来自官方仓库、对应同一 Tag 提交，且签名构建、权限检查和资产保存均成功，然后复用该 AAB，不重编译、不移动 Tag。复用来源仅接受原始构建工作流，不接受仅上传的重试运行。

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

该能力只对从 Google Play 安装、且当前账号有权获取更高 `versionCode` 的构建生效。如需真机回归，可通过 internal track 或 Internal App Sharing 验证：从旧版本启动，接受 Play 更新，等待后台下载完成，再确认重启后版本已升级。该检查不作为正式上架的前置门禁。直接侧载的 APK 仍可手动查看 GitHub Releases，但不会自行下载安装包。

Leeef Reader 不申请 `android.permission.REQUEST_INSTALL_PACKAGES`。发布工作流会检查合并后的 manifest，防止依赖意外加入 APK 自安装权限；请勿为侧载更新绕过这一约束。

## App Store Connect / TestFlight

在 GitHub 创建受保护的 `app-store` Environment：

- Variables：`APPSTORE_ISSUER_ID`、`APPSTORE_API_KEY_ID`。
- Secrets：`APPSTORE_API_PRIVATE_KEY`（`.p8` 内容）、`APPSTORE_CERTIFICATES_FILE_BASE64`（Apple Distribution `.p12` 的 base64）、`APPSTORE_CERTIFICATES_PASSWORD`。

API Key 至少需要 App Manager 权限。`tauri-release.yml` 的 iOS job 使用 `app-store` Environment：导入 Apple Distribution 证书，下载 bundle id `dev.leeef.leeefReader` 的 App Store provisioning profile，执行 `npx tauri ios build --export-method app-store-connect`，把 IPA 上传到 App Store Connect，从 GitHub Release 双语说明生成“版本更新内容”，关联精确版本与 build，提交审核，并设置为审核通过后自动发布。关闭 `upload_appstore` 可复用已经处理完成的 build；关闭 `submit_appstore` 才会停止在仅上传/TestFlight 状态。当前 Tauri 包没有 Flutter 时代的 Share Extension；不要再去下载 `dev.leeef.leeefReader.ShareExtension` 的 profile。

`CFBundleShortVersionString` 来自 `package.json` 版本。`CFBundleVersion` 默认是 `major * 1000000 + minor * 1000 + patch`（例如 2.2.0 → `2002000`），高于 Flutter 最后一次的 `25`。同一版本再次上传时用 `ios_build_number` 覆盖。工作流固定使用对应版本与 build 送审；上传成功、送审成功和正式上架是三个不同状态，发布审计必须分别记录。若 Apple 因缺少商店资料、协议或合规问卷拒绝送审，工作流必须失败并在 App Store Connect 补齐阻塞项后重跑，不能把仅上传成功当成发版完成。

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

手动执行工作流可选择无签名构建用于内部测试。正式发布时，先创建 Draft Release，再以该 Draft 的 Tag 作为 `release_tag` 运行工作流；工作流会从 Tag 构建、签名、公证，并向 Draft 附加 DMG、供静默下载的 ZIP 以及签名的 `appcast.xml`。Tag 必须与 `pubspec.yaml` 的版本一致，例如版本 `1.0.0+2` 对应 `v1.0.0`。工作流成功且 Draft 中三项资产齐全后立即公开 Release；`published` 事件不会重新构建，只审计已有资产。已安装的 macOS 客户端启动时立即检查，持续运行期间每 5 分钟静默检查并下载；下载、验签和解压完成后才提示用户重启安装，选择稍后时正常退出应用也会完成安装。

macOS 客户端启用了 App Sandbox，因此 Release 签名必须保留 Sparkle 要求的 `<bundle-id>-spks` 与 `<bundle-id>-spki` Mach lookup 权限。`tool/verify_macos_bundle.sh` 会从最终签名产物中核验这两项；缺失时安装器无法把下载结果交回应用，发布必须中止。

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
3. 等待当前源码提交的跨平台 CI 全部通过；该工作流执行 `apps/reader` 的 npm 测试/构建，以及 `apps/reader/src-tauri` 的 `cargo test --lib`。发布规划器会直接复用这一结果，不重复执行同一套门禁。
4. 创建 `vX.Y.Z` Draft Release，使用同一 Tag 运行 `Tauri signed release`（默认 `platforms: all`），确认 macOS DMG/ZIP 与 Android APK/AAB 已上传且工作流成功。
5. 立即公开 GitHub Release。Google Play production 与 App Store Connect 上传由 `tauri-release.yml` 直接执行，无需先经过测试渠道，也不得为此询问用户。建议检查真机导入、阅读、分享导入、后台音频、同步和 Android 更新流程；如未执行，如实记录，不阻塞正式上架或送审，也不得将其标记为通过。
6. 在 Intel 与 Apple Silicon Mac 上验证 DMG 可挂载、拖入 Applications，并运行 `spctl --assess --type execute --verbose "Leeef Reader.app"`；从前一正式版本启动应用，确认新版 ZIP 静默下载后出现“重启以更新”，重启后版本号已更新。该 macOS 验收仍按发布后行为执行，默认不覆盖安装开发者机器上的现有应用。
7. 确认 `tauri-release.yml` 的 macOS、Android、iOS job 已成功；分别核验 Play 生产轨道、App Store Connect 处理/送审和正式上架状态，不将上传成功等同于上架成功。
