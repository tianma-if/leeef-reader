#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

version="$(sed -nE 's/^version:[[:space:]]*([^+[:space:]]+).*/\1/p' pubspec.yaml)"
build_number="$(sed -nE 's/^version:[[:space:]]*[^+[:space:]]+\+([0-9]+).*/\1/p' pubspec.yaml)"
test -n "$version"
test -n "$build_number"
flutter config --build-dir=build.noindex
flutter pub get
flutter build macos --release

products_dir="$repo_dir/build.noindex/macos/Build/Products/Release"
app_path="$(find "$products_dir" -maxdepth 1 -type d -name '*.app' -print -quit)"
test -n "$app_path"
executable_name="$(defaults read "$app_path/Contents/Info" CFBundleExecutable)"
executable_archs="$(lipo -archs "$app_path/Contents/MacOS/$executable_name")"
if [[ "$executable_archs" == *arm64* && "$executable_archs" == *x86_64* ]]; then
  distribution_arch="universal"
elif [[ "$executable_archs" == *arm64* ]]; then
  distribution_arch="arm64"
elif [[ "$executable_archs" == *x86_64* ]]; then
  distribution_arch="x64"
else
  echo "Unsupported macOS executable architectures: $executable_archs" >&2
  exit 1
fi

pdfium_binary="$app_path/Contents/Frameworks/PDFium.framework/PDFium"
if [[ -f "$pdfium_binary" ]]; then
  expected_pdfium_id='@rpath/PDFium.framework/PDFium'
  bundle_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
    "$app_path/Contents/Frameworks/PDFium.framework/Resources/Info.plist")"
  test "$bundle_executable" = 'PDFium'
  otool -D "$pdfium_binary" | grep -Fxq "$expected_pdfium_id"
  if otool -D "$pdfium_binary" | awk '/^@rpath\// { print }' | grep -Fvxq "$expected_pdfium_id"; then
    echo "PDFium has an invalid Mach-O install name:" >&2
    otool -D "$pdfium_binary" >&2
    exit 1
  fi
fi

# Sign nested code explicitly before the app: codesign --deep may preserve an
# already-valid framework signed by a different team, which dyld then refuses
# to load. An unsigned local build uses an ad-hoc identity; release builds
# replace it with the configured Developer ID identity.
signing_identity="${MACOS_CERTIFICATE_NAME:--}"
code_sign_args=(
  --force
  --sign "$signing_identity"
)
if [[ "$signing_identity" != "-" ]]; then
  code_sign_args+=(--options runtime --timestamp)
fi

while IFS= read -r -d '' nested_code; do
  codesign "${code_sign_args[@]}" "$nested_code"
done < <(
  find "$app_path/Contents/Frameworks" \
    \( -type d -name '*.xpc' -o -type d -name '*.app' -o -type f -name '*.dylib' \) \
    -print0
)

while IFS= read -r -d '' framework; do
  codesign "${code_sign_args[@]}" "$framework"
done < <(find "$app_path/Contents/Frameworks" -type d -name '*.framework' -print0)

codesign "${code_sign_args[@]}" \
  --entitlements "$repo_dir/macos/Runner/Release.entitlements" \
  "$app_path"
"$repo_dir/tool/verify_macos_bundle.sh" "$app_path"

output_dir="$repo_dir/build.noindex/distribution"
staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT
mkdir -p "$output_dir"
cp -R "$app_path" "$staging_dir/Leeef Reader.app"
ln -s /Applications "$staging_dir/Applications"

dmg_path="$output_dir/Leeef-Reader-${version}-macos-${distribution_arch}.dmg"
rm -f "$output_dir/Leeef-Reader-${version}-macos-"*.dmg
hdiutil create -volname "Leeef Reader" -srcfolder "$staging_dir" \
  -ov -format UDZO "$dmg_path"

if [[ -n "${MACOS_CERTIFICATE_NAME:-}" ]]; then
  codesign --force --timestamp --sign "$MACOS_CERTIFICATE_NAME" "$dmg_path"
  codesign --verify --verbose=2 "$dmg_path"
fi

if [[ -n "${APPLE_API_PRIVATE_KEY:-}" || -n "${APPLE_API_KEY_ID:-}" || -n "${APPLE_API_ISSUER_ID:-}" ]]; then
  : "${APPLE_API_PRIVATE_KEY:?APPLE_API_PRIVATE_KEY is required for notarization}"
  : "${APPLE_API_KEY_ID:?APPLE_API_KEY_ID is required for notarization}"
  : "${APPLE_API_ISSUER_ID:?APPLE_API_ISSUER_ID is required for notarization}"
  api_key_path="$staging_dir/AuthKey_${APPLE_API_KEY_ID}.p8"
  printf '%s' "$APPLE_API_PRIVATE_KEY" > "$api_key_path"
  chmod 600 "$api_key_path"
  xcrun notarytool submit "$dmg_path" --wait \
    --key "$api_key_path" \
    --key-id "$APPLE_API_KEY_ID" \
    --issuer "$APPLE_API_ISSUER_ID"
  xcrun stapler staple "$dmg_path"
  xcrun stapler validate "$dmg_path"
fi

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  zip_path="$output_dir/Leeef-Reader-${version}-macos-${distribution_arch}.zip"
  appcast_path="$output_dir/appcast.xml"
  sign_tool="$repo_dir/macos/Pods/Sparkle/bin/sign_update"
  test -x "$sign_tool"
  embedded_public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' \
    "$repo_dir/macos/Runner/Info.plist")"
  private_key_hex="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | \
    openssl base64 -d -A | xxd -p | tr -d '\n')"
  if [[ "${#private_key_hex}" -ne 64 ]]; then
    echo "SPARKLE_PRIVATE_KEY must be a base64-encoded 32-byte Ed25519 seed." >&2
    exit 1
  fi
  private_key_der="$staging_dir/sparkle-private.der"
  printf '302e020100300506032b657004220420%s' "$private_key_hex" | \
    xxd -r -p > "$private_key_der"
  derived_public_key="$(openssl pkey -inform DER -in "$private_key_der" \
    -pubout -outform DER | tail -c 32 | openssl base64 -A)"
  if [[ "$derived_public_key" != "$embedded_public_key" ]]; then
    echo "SPARKLE_PRIVATE_KEY does not match Info.plist SUPublicEDKey." >&2
    exit 1
  fi
  ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"
  signature_output="$(printf '%s\n' "$SPARKLE_PRIVATE_KEY" | \
    "$sign_tool" --ed-key-file - "$zip_path")"
  signature="$(sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p' <<<"$signature_output")"
  archive_length="$(sed -nE 's/.*length="([0-9]+)".*/\1/p' <<<"$signature_output")"
  test -n "$signature"
  test -n "$archive_length"
  published_at="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S %z')"
  archive_name="$(basename "$zip_path")"
  archive_url="https://github.com/tianma-if/leeef-reader/releases/download/v${version}/${archive_name}"
  release_url="https://github.com/tianma-if/leeef-reader/releases/tag/v${version}"
  {
    printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>'
    printf '%s\n' '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
    printf '%s\n' '  <channel>'
    printf '%s\n' '    <title>Leeef Reader updates</title>'
    printf '    <link>%s</link>\n' "$release_url"
    printf '%s\n' '    <description>Leeef Reader stable updates</description>'
    printf '%s\n' '    <language>zh-CN</language>'
    printf '%s\n' '    <item>'
    printf '      <title>Leeef Reader %s</title>\n' "$version"
    printf '      <link>%s</link>\n' "$release_url"
    printf '      <pubDate>%s</pubDate>\n' "$published_at"
    printf '%s\n' '      <sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>'
    printf '      <enclosure url="%s" sparkle:version="%s" sparkle:shortVersionString="%s" sparkle:edSignature="%s" length="%s" type="application/octet-stream"/>\n' \
      "$archive_url" "$build_number" "$version" "$signature" "$archive_length"
    printf '%s\n' '    </item>'
    printf '%s\n' '  </channel>'
    printf '%s\n' '</rss>'
  } > "$appcast_path"
  printf '%s\n' "$SPARKLE_PRIVATE_KEY" | \
    "$sign_tool" --ed-key-file - --disable-signing-warning "$appcast_path"
fi

echo "$dmg_path"
