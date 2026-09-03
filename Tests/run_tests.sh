#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Shared 引擎為平台無關，在 macOS host 上編譯測試。
# 只有 ClipboardProcessor 用 UIKit — 排除並以 Tests/Stubs/ 的 stub 取代。
EXCLUDE="ClipboardProcessor"

SOURCES=$(find Shared -maxdepth 1 -name '*.swift' | grep -Ev "$EXCLUDE" | sort -u)
TEST_SOURCES=$(find Tests -name '*.swift' | sort)

BINDIR=/tmp/ohmybias_ios_tests
mkdir -p "$BINDIR"
# 測試 binary 的 Bundle.main 即其所在目錄 — 把資料檔放在旁邊
cp Resources/phrases.bin Resources/zhuyin_data.bin Resources/pinyin_data.bin Resources/char_freq.bin Resources/s2t.json Resources/t2s.json "$BINDIR/"

echo "Compiling test runner..."
swiftc \
    -module-name OhMyBiasTests \
    -target arm64-apple-macos14.0 \
    -sdk "$(xcrun --show-sdk-path)" \
    -O \
    -o "$BINDIR/ohmybias_tests" \
    $SOURCES $TEST_SOURCES

echo "Running tests..."
(cd "$BINDIR" && ./ohmybias_tests)
