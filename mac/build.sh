#!/bin/bash
# 编译 Focus Todo.app（只需要 Xcode 命令行工具，不需要完整的 Xcode）
# 用法：./build.sh          编译到 build/ 并打开
#       ./build.sh install  编译后安装到「应用程序」文件夹
set -e
cd "$(dirname "$0")"
APP="build/Focus Todo.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "› 编译 Swift…"
swiftc -O -target arm64-apple-macos13.0 Sources/*.swift -o "$APP/Contents/MacOS/FocusTodo" \
  -framework AppKit -framework WebKit -framework UserNotifications -framework CoreLocation

echo "› 打包资源…"
cp Info.plist "$APP/Contents/Info.plist"
# 界面与网页版共用：直接取仓库根目录的 index.html、字体和图标
mkdir -p "$APP/Contents/Resources/web"
cp ../index.html ../manifest.webmanifest "$APP/Contents/Resources/web/"
cp -R ../fonts ../icons "$APP/Contents/Resources/web/"

echo "› 生成图标…"
ICONSET=build/AppIcon.iconset && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s*2)); sips -z $d $d Resources/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "› 签名（本机使用的临时签名）…"
codesign --force --deep --sign - "$APP"

if [ "$1" = "install" ]; then
  rm -rf "/Applications/Focus Todo.app"
  cp -R "$APP" "/Applications/"
  echo "✓ 已安装到「应用程序」"
  open "/Applications/Focus Todo.app"
else
  echo "✓ 编译完成：$APP"
  open "$APP"
fi
