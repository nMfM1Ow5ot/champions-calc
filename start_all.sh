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
swift reader.swift "$@"
