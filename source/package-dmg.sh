#!/bin/bash
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
source_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$here/AppInfo.plist")"
app="${1:-$here/../build/$source_version/天气菜单栏.app}"
[[ -d "$app" && "$app" == *.app ]] || { echo '请先构建 .app，或传入已构建的应用路径' >&2; exit 1; }
/usr/bin/codesign --verify --strict "$app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
dest="${2:-$(dirname "$app")/天气菜单栏-v$version.dmg}"
[[ "$dest" == *.dmg && ! -e "$dest" && ! -L "$dest" ]] || { echo '目标须为尚不存在的 .dmg 路径' >&2; exit 1; }
mkdir -p "$(dirname "$dest")"

stage="$(mktemp -d "${TMPDIR:-/tmp}/weather-menu-dmg.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
mkdir "$stage/volume"
/usr/bin/ditto "$app" "$stage/volume/天气菜单栏.app"
ln -s /Applications "$stage/volume/Applications"

image="$stage/WeatherMenu.dmg"
/usr/bin/hdiutil create -quiet -srcfolder "$stage/volume" -fs HFS+ -format UDZO \
  -volname "天气菜单栏 v$version" "$image"
/usr/bin/hdiutil verify -quiet "$image"
mv -n "$image" "$dest"
[[ ! -e "$image" ]] || { echo '打包期间目标已被占用，未覆盖' >&2; exit 1; }
printf '%s\n' "$dest"
