#!/bin/zsh
# 编译并打包成 build/release/OpenAnticater.app（Apple Silicon 原生，本地签名）。
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
swift build -c "$CONFIG" --product OpenAnticater
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/$CONFIG/OpenAnticater.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/OpenAnticater" "$APP/Contents/MacOS/OpenAnticater"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

codesign --force --sign - --options runtime "$APP"
echo "已生成 $APP"
