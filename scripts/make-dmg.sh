#!/bin/zsh
# 把 build/release/OpenAnticater.app 做成可拖拽安装的 DMG（App + 「应用程序」快捷方式）。
# 先运行 ./scripts/build-app.sh。用法：./scripts/make-dmg.sh [输出目录，默认 dist]
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/release/OpenAnticater.app"
[[ -d "$APP" ]] || { echo "找不到 $APP，请先运行 ./scripts/build-app.sh" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
OUT_DIR="${1:-dist}"
DMG="$OUT_DIR/OpenAnticater-$VERSION-arm64.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/OpenAnticater.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$OUT_DIR"
rm -f "$DMG"
hdiutil create -quiet -volname "OpenAnticater $VERSION" -srcfolder "$STAGE" -fs HFS+ -format ULFO "$DMG"
hdiutil verify -quiet "$DMG"
echo "$DMG"
