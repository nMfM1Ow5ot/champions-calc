#!/bin/bash
# UI サーバ + 画面リーダーをまとめて起動する (Mac用)
# これ1つで両方立ち上がる。終了は Ctrl+C (両方止まる)。
# 引数はリーダーへそのまま渡る (例: bash start_all.sh --debug)
cd "$(dirname "$0")"

# 前のフォルダで起動したままの旧サーバがポート 8765 を掴んでいると
# 新しいサーバが起動できないので、先に止める
OLD=$(lsof -ti tcp:8765 2>/dev/null)
if [ -n "$OLD" ]; then
  echo "起動中の旧サーバを停止します (PID: $OLD)"
  kill $OLD 2>/dev/null
  sleep 1
fi

# 起動前に同期を1回済ませておく。リーダーが起動直後に落ちるような版が
# ディスクにあると、並行起動では同期が届く前に落ちて修正版が永遠に
# 届かなくなる (2026-11-20 の実例)。先に同期すれば、起動するリーダーは
# 常に最新の状態になる。--force で版の記録と無関係に全ファイルを照合する。
echo "最新のファイルに同期します..."
python3 sync_ui.py --force || true

# UI サーバを裏で起動し、終了時に一緒に止める
python3 serve.py &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null' EXIT INT TERM

sleep 1
echo "UI はブラウザで http://localhost:8765/ui.html を開いてください (自動では開きません)"
echo "リーダーを起動します (終了は Ctrl+C で両方止まります)"

# リーダーは表で起動
# 終了コード 42 (新しいリーダーが同期で届いた合図) のときは再起動する。
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
  if [ $code -eq 0 ] || [ $code -eq 130 ]; then
    exit $code
  fi
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
