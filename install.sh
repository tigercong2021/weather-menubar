#!/bin/bash
# Weather Menu Bar: no Homebrew, Git, sudo, or preinstalled developer tools required.
# The first Apple developer-tools installation requires the user's GUI consent.
# Bash 3.2 compatible. Keep the entry-point call last for curl | bash usage.
set -Eeuo pipefail

weather_work=""
weather_phase="检查安装条件"

say() { printf '%s\n' "$*"; }
fail() { printf '安装未完成：%s\n' "$*" >&2; exit 1; }

cleanup() {
  # Delete only the private temporary directory created by this invocation.
  case "$weather_work" in
    */weather-menu-install.??????) rm -rf -- "$weather_work" ;;
  esac
}

tools_ready() {
  local sdk
  sdk="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null)" || return 1
  case "${sdk%%.*}" in ''|*[!0-9]*) return 1 ;; esac
  [[ "${sdk%%.*}" -ge 26 ]] || return 1
  xcrun clang --version >/dev/null 2>&1 || return 1
  xcrun swiftc --version >/dev/null 2>&1
}

select_tools() {
  # Honor working selected tools. A usable standalone CLT may coexist with old Xcode.
  if xcode-select -p >/dev/null 2>&1 && tools_ready; then return 0; fi
  local previous="${DEVELOPER_DIR-}" had_override="${DEVELOPER_DIR+x}"
  if [[ -d /Library/Developer/CommandLineTools ]]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
    if tools_ready; then return 0; fi
    if [[ "$had_override" == x ]]; then
      export DEVELOPER_DIR="$previous"
    else
      unset DEVELOPER_DIR
    fi
  fi
  return 1
}

ensure_tools() {
  if select_tools; then return; fi
  weather_phase="安装苹果开发工具"
  say '需要苹果 Command Line Tools（含 macOS 26 或更新 SDK），无需 Homebrew。'
  if xcode-select --install; then
    say '请在苹果弹窗中点“安装”，并保持终端打开；安装完成后会自动继续。'
  else
    say '请在“系统设置 → 通用 → 软件更新”中更新 Command Line Tools。'
    say '若使用完整 Xcode，请在 Xcode → Settings → Locations 中选择新版 Command Line Tools，并完成许可确认。'
    open 'x-apple.systempreferences:com.apple.Software-Update-Settings.extension' || true
  fi
  say '最多等待 60 分钟；可按 Control+C 退出，准备好工具后重新运行同一条安装命令。'
  local deadline=$((SECONDS + 3600))
  until select_tools; do
    [[ "$SECONDS" -lt "$deadline" ]] || fail '未检测到可用的 macOS 26+ 开发工具。请完成安装/更新或在 Xcode 中选择新版工具，再重新运行安装命令。'
    sleep 10
  done
}

main() {
  local install_dir="$HOME/Applications" launch_app=1 app os major archive_url
  # Optional arguments allow a separate installation directory or no launch.
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --install-dir)
        [[ "$#" -ge 2 ]] || fail '--install-dir 后需要绝对目录路径。'
        install_dir="$2"; shift 2 ;;
      --no-open) launch_app=0; shift ;;
      *) fail "未知参数：$1" ;;
    esac
  done
  [[ "$install_dir" == /* ]] || fail '安装目录必须是绝对路径。'
  [[ "$(uname -s)" == Darwin ]] || fail '本应用仅支持 macOS。'
  [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]] || fail '需要 Apple Silicon（M 系列芯片）Mac。'
  os="$(sw_vers -productVersion)"
  major="${os%%.*}"
  case "$major" in ''|*[!0-9]*) fail '无法识别 macOS 版本。' ;; esac
  [[ "$major" -ge 26 ]] || fail "当前为 macOS ${os}，需要 macOS 26 或更新版本。"
  app="$install_dir/天气菜单栏.app"
  [[ ! -e "$app" && ! -L "$app" ]] || fail "已存在同名应用：${app}。本脚本用于首次安装，不会覆盖它。"
  ensure_tools

  weather_work="$(mktemp -d "${TMPDIR:-/tmp}/weather-menu-install.XXXXXX")"
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'weather_status=$?; printf "安装未完成：%s失败（错误码 %s）。\n" "$weather_phase" "$weather_status" >&2; exit "$weather_status"' ERR

  # Pin the public v2.0.0 source commit, independently of future main/tag changes.
  archive_url='https://github.com/tigercong2021/weather-menubar/archive/fd32e3ce7e9e7dc66c3ae565efe1bb18f58211a6.tar.gz'
  weather_phase="下载 V2.0 源码"
  say '正在从 GitHub 下载天气菜单栏 V2.0…'
  curl --fail --location --show-error --proto '=https' --tlsv1.2 \
    --retry 3 --connect-timeout 30 --max-time 900 \
    "$archive_url" -o "$weather_work/source.tar.gz"
  weather_phase="解压源码"
  mkdir "$weather_work/source"
  tar -xzf "$weather_work/source.tar.gz" -C "$weather_work/source" --strip-components=1
  [[ -f "$weather_work/source/source/build.sh" ]] || fail '下载内容缺少构建脚本。'

  weather_phase="编译应用"
  say '正在编译和签名，请稍候…'
  say '此开源构建使用本机临时签名，未经 Apple 公证。'
  # Keep the build script's temporary intermediates inside our private directory.
  TMPDIR="$weather_work/" bash "$weather_work/source/source/build.sh" "$weather_work/天气菜单栏.app"
  codesign --verify --strict "$weather_work/天气菜单栏.app"

  weather_phase="安装应用"
  mkdir -p "$install_dir"
  [[ ! -e "$app" && ! -L "$app" ]] || fail "安装位置已被占用：${app}。"
  # Pass the parent directory, so a concurrently created .app cannot receive a nested app.
  mv -n "$weather_work/天气菜单栏.app" "$install_dir/"
  [[ ! -e "$weather_work/天气菜单栏.app" && -d "$app" ]] || fail '应用未能移入安装目录，未覆盖已有应用。'
  say "安装完成：$app"
  if [[ "$launch_app" -eq 1 ]]; then
    if open "$app"; then
      say '请查看屏幕顶部菜单栏。可按需允许定位，也可以手动选择城市。'
    else
      say '应用已安装，但自动启动未成功。请在访达中打开上述应用。'
    fi
  fi
}

main "$@"
