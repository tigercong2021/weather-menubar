#!/bin/bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$here/AppInfo.plist")"
dest="${1:-$here/../build/$version/天气菜单栏.app}"
[[ "$dest" == *.app && ! -e "$dest" && ! -L "$dest" ]] || { echo '目标须为尚不存在的 .app 路径' >&2; exit 1; }
[[ ! -e "$dest.astronomy.o" ]] || { echo '天文构建证据路径已存在' >&2; exit 1; }
mkdir -p "$(dirname "$dest")"
stage="$(mktemp -d "${TMPDIR:-/tmp}/weather-menu-build.XXXXXX")"
app="$stage/天气菜单栏.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$here/AppInfo.plist" "$app/Contents/Info.plist"
cp -R "$here/../assets/temps" "$app/Contents/Resources/TempsWeather"
cp -R "$here/../assets/temps-effects" "$app/Contents/Resources/TempsEffects"
cp -R "$here/../assets/outfit-icons/v4/compact" "$app/Contents/Resources/OutfitIcons"
cp "$here/../assets/AppIcon.icns" "$app/Contents/Resources/"
mkdir -p "$app/Contents/Resources/Licenses"
cp "$here/../LICENSE" "$app/Contents/Resources/Licenses/WeatherMenu-MIT.txt"
cp "$here/../assets/outfit-icons/v4/ASSET-NOTICE.md" "$app/Contents/Resources/Licenses/OutfitIcons-Notice.md"
cp "$here/../assets/outfit-icons/v4/LICENSE" "$app/Contents/Resources/Licenses/OutfitIcons-MIT.txt"
cp "$here/../vendor/astronomy-engine/LICENSE" "$app/Contents/Resources/Licenses/AstronomyEngine-MIT.txt"
cp "$here/../assets/star-catalog/original/CC-BY-SA-4.0.txt" "$app/Contents/Resources/Licenses/BrightStarCatalog-CC-BY-SA-4.0.txt"
cp "$here/../assets/star-catalog/README.md" "$app/Contents/Resources/Licenses/BrightStarCatalog-Attribution.md"
cp "$here/../assets/star-catalog/bright-stars-v41-mag3.json" "$app/Contents/Resources/Licenses/BrightStarCatalog-DerivedData.json"
if [[ -d "$here/../assets/weather-scenes/runtime" ]]; then
  cp "$here/../assets/weather-scenes/ASSET-NOTICE.md" "$app/Contents/Resources/Licenses/WeatherScenes-Notice.md"
  mkdir -p "$app/Contents/Resources/WeatherScenes"
  # Package runtime media only. Local validation reports are not app resources.
  for media in "$here/../assets/weather-scenes/runtime/"*.mp4 "$here/../assets/weather-scenes/runtime/"*.jpg; do
    [[ -f "$media" ]] && cp "$media" "$app/Contents/Resources/WeatherScenes/"
  done
fi
xcrun clang -O2 -target arm64-apple-macosx26.0 -c "$here/../vendor/astronomy-engine/astronomy.c" -o "$stage/astronomy.o"
xcrun swiftc -swift-version 6 -O -target arm64-apple-macosx26.0 -module-name WeatherMenu \
  -module-cache-path "${TMPDIR:-/tmp}/tiger-weather-menu-swift-cache" \
  -I "$here/../vendor/astronomy-engine" "$here/"*.swift "$stage/astronomy.o" -o "$app/Contents/MacOS/WeatherMenu"
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - --identifier local.tigercong.weathermenu "$app"
codesign --verify --strict "$app"
mv -n "$app" "$dest"
[[ ! -e "$app" ]] || { echo '构建期间目标已被占用，未覆盖' >&2; exit 1; }
# Preserve the intermediate object with the release evidence instead of leaving
# it in the temporary staging directory.
mv -n "$stage/astronomy.o" "$dest.astronomy.o"
rmdir "$stage"
printf '%s\n' "$dest"
