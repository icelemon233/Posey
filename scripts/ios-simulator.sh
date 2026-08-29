#!/bin/zsh

set -euo pipefail

POSEY_ROOT="${0:A:h:h}"
POSEY_DEVELOPER_DIR="${POSEY_DEVELOPER_DIR:-$POSEY_ROOT/Xcode_26.1.1/Xcode.app/Contents/Developer}"
POSEY_RUNTIME="${POSEY_RUNTIME:-com.apple.CoreSimulator.SimRuntime.iOS-26-1}"
POSEY_DEVICE_NAME="${POSEY_DEVICE_NAME:-Posey iPhone 17 Pro}"
POSEY_DEVICE_TYPE="${POSEY_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro}"
POSEY_APP="$POSEY_ROOT/ios/DerivedData/Build/Products/Debug-iphonesimulator/App.app"

if [[ ! -x "$POSEY_DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  print -u2 "找不到项目内 Xcode：$POSEY_DEVELOPER_DIR"
  exit 1
fi

cd "$POSEY_ROOT"
npm run build
npx cap copy ios

DEVELOPER_DIR="$POSEY_DEVELOPER_DIR" xcodebuild \
  -quiet \
  -workspace ios/App/App.xcworkspace \
  -scheme App \
  -sdk iphonesimulator \
  -derivedDataPath ios/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  build

if [[ -z "${POSEY_SIMULATOR_UDID:-}" ]]; then
  POSEY_SIMULATOR_UDID="$(
    DEVELOPER_DIR="$POSEY_DEVELOPER_DIR" xcrun simctl list devices -j |
      jq -r --arg runtime "$POSEY_RUNTIME" --arg name "$POSEY_DEVICE_NAME" \
        '.devices[$runtime][]? | select(.name == $name) | .udid' |
      head -1
  )"
fi

if [[ -z "$POSEY_SIMULATOR_UDID" ]]; then
  if ! DEVELOPER_DIR="$POSEY_DEVELOPER_DIR" xcrun simctl list runtimes | rg -q 'iOS 26\.1'; then
    print -u2 "找不到 iOS 26.1 runtime。请先用 Xcode 26 执行：xcodebuild -downloadPlatform iOS"
    exit 1
  fi
  POSEY_SIMULATOR_UDID="$(
    DEVELOPER_DIR="$POSEY_DEVELOPER_DIR" xcrun simctl create \
      "$POSEY_DEVICE_NAME" \
      "$POSEY_DEVICE_TYPE" \
      "$POSEY_RUNTIME"
  )"
fi

DEVELOPER_DIR="$POSEY_DEVELOPER_DIR" xcrun simctl boot "$POSEY_SIMULATOR_UDID" 2>/dev/null || true
DEVELOPER_DIR="$POSEY_DEVELOPER_DIR" xcrun simctl bootstatus "$POSEY_SIMULATOR_UDID" -b
DEVELOPER_DIR="$POSEY_DEVELOPER_DIR" xcrun simctl install "$POSEY_SIMULATOR_UDID" "$POSEY_APP"
DEVELOPER_DIR="$POSEY_DEVELOPER_DIR" xcrun simctl launch \
  --terminate-running-process \
  "$POSEY_SIMULATOR_UDID" \
  com.posey.camera

print "Posey 已在 iPhone 17 Pro / iOS 26.1 模拟器启动。"
