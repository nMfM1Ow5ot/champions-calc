#!/bin/bash
# Champions 対戦画面リーダーを起動する (Mac用)
# 初回は「画面収録」の許可ダイアログが出たら許可してください (ターミナルに対して許可)。
cd "$(dirname "$0")"
swift reader.swift "$@"
