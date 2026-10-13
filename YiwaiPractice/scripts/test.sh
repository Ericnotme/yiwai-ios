#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcodebuild -project YiwaiPractice.xcodeproj -scheme YiwaiPractice \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -derivedDataPath build -parallel-testing-enabled NO \
  test CODE_SIGNING_ALLOWED=NO
