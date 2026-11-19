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
# 版本号（CFBundleShortVersionString）写在 Resources/Info.plist 里；
# 构建号用提交数，保证只增不减。CI 里需要完整历史（fetch-depth: 0）。
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

codesign --force --sign - --options runtime "$APP"
echo "已生成 $APP"
