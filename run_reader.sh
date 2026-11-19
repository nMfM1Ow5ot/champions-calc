#!/bin/bash
# Champions 対戦画面リーダーを起動する (Mac用)
# 初回は「画面収録」の許可ダイアログが出たら許可してください (ターミナルに対して許可)。
cd "$(dirname "$0")"
# リーダーが終了コード 42 で抜けたら (新しいリーダーが同期で届いた合図)、
# そのまま新しい版で再起動する。それ以外の終了 (Ctrl+C 等) はそのまま終わる
while true; do
  swift reader.swift "$@"
  code=$?
  if [ $code -ne 42 ]; then exit $code; fi
  echo "リーダーを再起動します"
done
