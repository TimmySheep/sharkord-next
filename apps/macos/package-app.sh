#!/bin/sh
set -eu

root="$(cd "$(dirname "$0")" && pwd)"
configuration="${1:-release}"
app_path="${2:-$root/.build/cove.app}"

if [ -e "$app_path" ]; then
  printf 'refusing to overwrite existing app bundle: %s\n' "$app_path" >&2
  exit 1
fi

swift build --package-path "$root" -c "$configuration"
products="$(swift build --package-path "$root" -c "$configuration" --show-bin-path)"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$products/SharkordMac" "$app_path/Contents/MacOS/cove"
cp -R "$products/SharkordMac_SharkordMac.bundle" "$app_path/Contents/Resources/"
cp "$root/Resources/cove.icns" "$app_path/Contents/Resources/cove.icns"
cp "$root/Resources/AppInfo.plist" "$app_path/Contents/Info.plist"

for locale_bundle in "$root"/Resources/*.lproj; do
  if [ -d "$locale_bundle" ]; then
    cp -R "$locale_bundle" "$app_path/Contents/Resources/"
  fi
done

plutil -lint "$app_path/Contents/Info.plist"
codesign --force --deep --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
printf 'created %s\n' "$app_path"
