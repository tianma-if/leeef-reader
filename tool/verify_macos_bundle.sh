#!/usr/bin/env bash
set -euo pipefail

app_path="${1:?Usage: verify_macos_bundle.sh /path/to/App.app}"
executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
  "$app_path/Contents/Info.plist")"
pdfium_framework="$app_path/Contents/Frameworks/PDFium.framework"
pdfium_binary="$pdfium_framework/PDFium"
expected_pdfium_id='@rpath/PDFium.framework/PDFium'

test -f "$app_path/Contents/MacOS/$executable_name"
test -f "$pdfium_binary"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
  "$pdfium_framework/Resources/Info.plist")" = 'PDFium'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  "$pdfium_framework/Resources/Info.plist")" = 'com.pdfium.PDFium'

pdfium_link_found=false
while IFS= read -r candidate; do
  if /usr/bin/otool -L "$candidate" 2>/dev/null | \
      /usr/bin/grep -Fq "$expected_pdfium_id"; then
    pdfium_link_found=true
    break
  fi
done < <(
  /usr/bin/find "$app_path/Contents/MacOS" -maxdepth 1 -type f \
    \( -name "$executable_name" -o -name '*.dylib' \) -print
)
if [[ "$pdfium_link_found" != true ]]; then
  echo "No app executable links $expected_pdfium_id" >&2
  exit 1
fi
/usr/bin/otool -D "$pdfium_binary" | \
  /usr/bin/grep -Fxq "$expected_pdfium_id"
if /usr/bin/otool -D "$pdfium_binary" | \
    /usr/bin/awk '/^@rpath\// { print }' | \
    /usr/bin/grep -Fvxq "$expected_pdfium_id"; then
  echo "PDFium install names differ between architectures:" >&2
  /usr/bin/otool -D "$pdfium_binary" >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"
