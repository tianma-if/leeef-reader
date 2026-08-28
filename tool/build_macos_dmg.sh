#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

version="$(sed -nE 's/^version:[[:space:]]*([^+[:space:]]+).*/\1/p' pubspec.yaml)"
flutter pub get
flutter build macos --release

products_dir="$repo_dir/build/macos/Build/Products/Release"
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
  find "$app_path/Contents/Frameworks" -maxdepth 1 \
    \( -type d -name '*.framework' -o -type f -name '*.dylib' \) \
    -print0
)

codesign "${code_sign_args[@]}" \
  --entitlements "$repo_dir/macos/Runner/Release.entitlements" \
  "$app_path"
"$repo_dir/tool/verify_macos_bundle.sh" "$app_path"

output_dir="$repo_dir/build/distribution"
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

echo "$dmg_path"
