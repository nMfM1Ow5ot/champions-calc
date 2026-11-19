#!/bin/bash
# Champions ダメージ計算UIをローカルで開く (Mac用)
cd "$(dirname "$0")"
# 前のフォルダで起動したままの旧サーバがポート 8765 を掴んでいると
# 新しいサーバが起動できないので、先に止める
OLD=$(lsof -ti tcp:8765 2>/dev/null)
if [ -n "$OLD" ]; then
  echo "起動中の旧サーバを停止します (PID: $OLD)"
  kill $OLD 2>/dev/null
  sleep 1
fi
echo "http://localhost:8765/ui.html をブラウザで開いてください (終了は Ctrl+C)"
python3 serve.py
