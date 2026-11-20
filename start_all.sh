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
echo "UI をブラウザで開きます: http://localhost:8765/ui.html"
if command -v open >/dev/null 2>&1; then
  open "http://localhost:8765/ui.html" 2>/dev/null
fi
echo "リーダーを起動します (終了は Ctrl+C で両方止まります)"

# リーダーは表で起動
# 終了コード 42 (新しいリーダーが同期で届いた合図) のときだけ再起動する
while true; do
  swift reader.swift "$@"
  code=$?
  if [ $code -ne 42 ]; then
    exit $code
  fi
  echo "リーダーを再起動します"
done
