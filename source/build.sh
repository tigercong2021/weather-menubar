#!/bin/bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$here/AppInfo.plist")"
dest="${1:-$here/../build/$version/天气菜单栏.app}"
[[ "$dest" == *.app && ! -e "$dest" && ! -L "$dest" ]] || { echo '目标须为尚不存在的 .app 路径' >&2; exit 1; }
mkdir -p "$(dirname "$dest")"
stage="$(mktemp -d "${TMPDIR:-/tmp}/weather-menu-build.XXXXXX")"
app="$stage/天气菜单栏.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$here/AppInfo.plist" "$app/Contents/Info.plist"
cp -R "$here/../assets/temps" "$app/Contents/Resources/TempsWeather"
cp -R "$here/../assets/temps-effects" "$app/Contents/Resources/TempsEffects"
cp "$here/../assets/AppIcon.icns" "$app/Contents/Resources/"
xcrun swiftc -swift-version 6 -O -target arm64-apple-macosx26.0 -module-name WeatherMenu \
  -module-cache-path "${TMPDIR:-/tmp}/tiger-weather-menu-swift-cache" \
  "$here/"*.swift -o "$app/Contents/MacOS/WeatherMenu"
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - --identifier local.tigercong.weathermenu "$app"
codesign --verify --strict "$app"
mv -n "$app" "$dest"
[[ ! -e "$app" ]] || { echo '构建期间目标已被占用，未覆盖' >&2; exit 1; }
rmdir "$stage"
printf '%s\n' "$dest"
