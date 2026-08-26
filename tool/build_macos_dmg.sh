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

if [[ -n "${MACOS_CERTIFICATE_NAME:-}" ]]; then
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$repo_dir/macos/Runner/Release.entitlements" \
    --sign "$MACOS_CERTIFICATE_NAME" "$app_path"
  codesign --verify --deep --strict --verbose=2 "$app_path"
fi

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
