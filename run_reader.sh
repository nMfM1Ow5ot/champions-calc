#!/bin/bash
# Champions 対戦画面リーダーを起動する (Mac用)
# 初回は「画面収録」の許可ダイアログが出たら許可してください (ターミナルに対して許可)。
cd "$(dirname "$0")"
# リーダーが終了コード 42 で抜けたら (新しいリーダーが同期で届いた合図)、
# そのまま新しい版で再起動する。
# それ以外の異常終了 (クラッシュ等) でも自動で再起動し、復旧を待つ。
# ただし起動直後に落ち続ける場合は無限ループを避けるため 5 回で諦める。
# Ctrl+C (130) と正常終了 (0) はそのまま終わる
CRASHES=0
while true; do
  START=$(date +%s)
  swift reader.swift "$@"
  code=$?
  if [ $code -eq 42 ]; then
    echo "リーダーを再起動します"
    CRASHES=0
    continue
  fi
  if [ $code -eq 0 ] || [ $code -eq 130 ]; then exit $code; fi
  NOW=$(date +%s)
  if [ $((NOW - START)) -lt 5 ]; then
    CRASHES=$((CRASHES + 1))
  else
    CRASHES=1
  fi
  if [ $CRASHES -ge 5 ]; then
    echo "リーダーが起動直後に繰り返し終了するため、自動再起動を中止します (コード: $code)"
    exit $code
  fi
  echo "リーダーが予期せず終了しました (コード: $code)。2 秒後に再起動します"
  sleep 2
done
