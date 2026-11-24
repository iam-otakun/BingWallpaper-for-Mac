#!/bin/bash
# BingWallpaper fork — 本地构建脚本（Dash 备，Fred 在 Mac 上运行）
# 用 DEVELOPER_DIR 直指 Xcode，不改系统 xcode-select，不需要 sudo。
set -e
cd "$(dirname "$0")"

if [ ! -d /Applications/Xcode.app ]; then
  echo "没找到 /Applications/Xcode.app，Xcode 还没装好。"
  exit 1
fi
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

echo "== Xcode 版本 =="
xcodebuild -version

echo "== 开始构建（Release，自签名 adhoc） =="
xcodebuild -project BingWallpaper.xcodeproj -scheme BingWallpaper \
  -configuration Release -derivedDataPath build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" \
  build

APP="build/Build/Products/Release/BingWallpaper.app"
echo "== 安装到 /Applications =="
rm -rf /Applications/BingWallpaper.app
cp -R "$APP" /Applications/BingWallpaper.app

echo "== 完成 =="
echo "BingWallpaper.app 已装到 /Applications，可以打开试了。"
