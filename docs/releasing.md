# 商店与 macOS 发布

Leeef Reader 使用三个相互独立的手动 GitHub Actions 工作流。首次发布前，应先在 Apple Developer、App Store Connect 和 Google Play Console 创建应用；已登记的标识不可随意更换。

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

产物位于 `build/distribution/`，包含应用和 `/Applications` 快捷方式。在 Developer ID Application 证书已经导入钥匙串时，可将 `MACOS_CERTIFICATE_NAME` 设置为证书名称或 SHA-1 指纹完成签名（存在同名证书时推荐使用指纹）；再提供 `APPLE_API_PRIVATE_KEY`、`APPLE_API_KEY_ID`、`APPLE_API_ISSUER_ID` 时，脚本会使用 App Store Connect API Key 提交公证并 staple ticket。

GitHub 的 `macos-distribution` Environment 配置：

- Variables：`APPSTORE_ISSUER_ID`、`APPSTORE_API_KEY_ID`。
- Secrets：`MACOS_CERTIFICATES_FILE_BASE64`、`MACOS_CERTIFICATES_PASSWORD`、`MACOS_CERTIFICATE_NAME`、`APPSTORE_API_PRIVATE_KEY`。

手动执行工作流可选择无签名构建用于内部测试，也可传入已有 GitHub Release 的 `release_tag`，将签名、公证后的 universal DMG 上传到该 Release。正式 GitHub Release 发布时，`published` 事件会自动从对应 tag 构建、签名、公证并附加 DMG；tag 必须与 `pubspec.yaml` 的版本一致，例如版本 `1.0.0+2` 对应 `v1.0.0`。

## 发布检查

1. 更新 `pubspec.yaml` 的 `version: X.Y.Z+N`；`N` 必须严格递增。
2. 运行 `flutter analyze` 与 `flutter test`。
3. 先发布 Play internal 与 TestFlight，完成真机导入、阅读、分享导入、后台音频和同步回归。
4. 在 Intel 与 Apple Silicon Mac 上验证 DMG 可挂载、拖入 Applications，并运行 `spctl --assess --type execute --verbose "Leeef Reader.app"`。
5. 最后在受保护 Environment 中批准生产轨道或 App Store 审核提交。
