#!/usr/bin/env bash
set -euo pipefail

source_framework="${BUILT_PRODUCTS_DIR:?}/PDFium.framework"
frameworks_dir="${TARGET_BUILD_DIR:?}/${FRAMEWORKS_FOLDER_PATH:?}"
destination_framework="$frameworks_dir/PDFium.framework"

if [[ ! -d "$source_framework" ]]; then
  echo "error: Xcode PDFium framework not found at $source_framework" >&2
  exit 1
fi

# pdfium_dart also produces a lowercase native asset on macOS. Flutter embeds
# that asset into the same case-insensitive path as pdfium_flutter's
# XCFramework, which can leave an uppercase bundle containing a lowercase
# Mach-O binary. Replace the entire destination with the XCFramework product.
rm -rf "$destination_framework"
/usr/bin/ditto "$source_framework" "$destination_framework"

pdfium_binary="$destination_framework/PDFium"
expected_id='@rpath/PDFium.framework/PDFium'
bundle_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
  "$destination_framework/Resources/Info.plist")"

if [[ "$bundle_executable" != "PDFium" ]]; then
  echo "error: PDFium CFBundleExecutable is '$bundle_executable', expected 'PDFium'" >&2
  exit 1
fi
if ! /usr/bin/otool -D "$pdfium_binary" | /usr/bin/grep -Fxq "$expected_id"; then
  echo "error: PDFium has an invalid Mach-O install name:" >&2
  /usr/bin/otool -D "$pdfium_binary" >&2
  exit 1
fi
if /usr/bin/otool -D "$pdfium_binary" | \
    /usr/bin/awk '/^@rpath\// { print }' | \
    /usr/bin/grep -Fvxq "$expected_id"; then
  echo "error: PDFium install names differ between architectures:" >&2
  /usr/bin/otool -D "$pdfium_binary" >&2
  exit 1
fi

# The replacement runs before Xcode signs the outer app. Sign the nested
# framework with the same build identity so the final app signature is valid.
if [[ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]]; then
  signing_identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
  if [[ -z "$signing_identity" ]]; then
    signing_identity='-'
  fi
  /usr/bin/codesign --force --sign "$signing_identity" \
    "$destination_framework"
fi
