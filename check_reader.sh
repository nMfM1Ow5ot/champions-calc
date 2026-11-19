#!/bin/bash
# reader.swift の構文・型チェック (macOS 不要)。
# Linux 用 Swift ツールチェーン + check/apple_stubs.swift (Apple API のスタブ) で
# swiftc -typecheck を通し、未定義の関数・壊れた構文・引数の不一致を検出する。
# 実行時の挙動 (OCR 精度や画面取り込み) までは検証できない。
set -e
cd "$(dirname "$0")"
SWIFTC="${SWIFTC:-$HOME/swift-toolchain/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin/swiftc}"
if [ ! -x "$SWIFTC" ]; then
  echo "swiftc が見つかりません: $SWIFTC" >&2
  echo "SWIFTC 環境変数でパスを指定してください" >&2
  exit 2
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# Apple フレームワークの import はスタブで置き換えるため取り除く (Foundation は残す)
grep -v -E '^import (Vision|CoreGraphics|AppKit|Network)$' reader.swift > "$WORK/main.swift"
"$SWIFTC" -typecheck "$WORK/main.swift" check/apple_stubs.swift
echo "reader.swift 型チェック OK"
