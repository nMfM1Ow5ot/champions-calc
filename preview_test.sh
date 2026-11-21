#!/bin/bash
# 見せ合い画面の同定テスト (Mac用ターミナル)
# 起動すると、reader と serve.py が動いていなければ自動で起動し、
# 準備ができたらキー待ちになる。見せ合い画面を表示した状態で
# sキーを押すと、その時点の画面を撮影して見せ合い同定を行い、
# 結果を Showdown のヘッダー形式 (<名前>'s team: …) で表示する。
# 撮影画像と検出結果は logs/ に preview_test_<日時>.jpg/.json として
# 保存され、serve.py が自動で送信する (ログ分析側で精度を分析する)。
# qキーで終了する。このスクリプトが起動した reader / serve.py は
# 終了時に一緒に止める (元から動いていたものには触れない)。
cd "$(dirname "$0")"

READER_LOG="preview_test_reader.log"
SERVE_LOG="preview_test_serve.log"
STARTED=()

# ポートが開いているか (接続できるか) だけを見る。/previewtest への
# HTTP リクエストは撮影そのものを引き起こすため、起動確認には使わない
port_open() {
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

# このスクリプトが起動したプロセスだけを止める。run_reader.sh 経由の
#場合はその子 (swift 本体) も一緒に止める
cleanup() {
  for pid in "${STARTED[@]}"; do
    for child in $(pgrep -P "$pid" 2>/dev/null); do
      kill "$child" 2>/dev/null
    done
    kill "$pid" 2>/dev/null
  done
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

need_reader=0
need_serve=0
port_open 8899 || need_reader=1
port_open 8765 || need_serve=1

if [ $need_reader -eq 1 ]; then
  echo "reader を起動します (出力は $READER_LOG へ)"
  bash run_reader.sh >> "$READER_LOG" 2>&1 &
  STARTED+=($!)
fi
if [ $need_serve -eq 1 ]; then
  echo "serve.py を起動します (出力は $SERVE_LOG へ)"
  # 備考のターミナル入力が効くよう、start_all.sh と同じく標準入力は
  # 制御端末 (/dev/tty) につなぐ
  if [ -e /dev/tty ]; then
    python3 serve.py < /dev/tty >> "$SERVE_LOG" 2>&1 &
  else
    python3 serve.py >> "$SERVE_LOG" 2>&1 &
  fi
  STARTED+=($!)
fi

if [ ${#STARTED[@]} -gt 0 ]; then
  echo "起動中です。準備が整うまでお待ちください…"
  ready=0
  deadline=$((SECONDS + 90))
  while [ $SECONDS -lt $deadline ]; do
    ready=1
    if [ $need_reader -eq 1 ] && ! port_open 8899; then ready=0; fi
    if [ $need_serve -eq 1 ] && ! port_open 8765; then ready=0; fi
    if [ $ready -eq 1 ]; then break; fi
    for pid in "${STARTED[@]}"; do
      if ! kill -0 "$pid" 2>/dev/null; then
        echo "起動したプロセスが終了しました。ログを確認してください: $READER_LOG / $SERVE_LOG"
        exit 1
      fi
    done
    sleep 1
  done
  if [ $ready -ne 1 ]; then
    echo "起動が時間内に終わりませんでした。ログを確認してください: $READER_LOG / $SERVE_LOG"
    exit 1
  fi
  echo "準備ができました"
else
  echo "reader と serve.py は起動済みです"
fi

do_capture() {
  RESP=$(curl -s --max-time 90 "http://localhost:8899/previewtest")
  RC=$?
  if [ $RC -ne 0 ] || [ -z "$RESP" ]; then
    if [ $RC -eq 28 ]; then
      echo "同定が時間内に終わりませんでした。画面が見せ合い画面か確認して、もう一度 sキーを押してください。"
    else
      echo "reader に接続できませんでした。reader が起動しているか確認してください。"
    fi
    return
  fi

  echo "$RESP" | python3 -c '
import json, os, sys, time

try:
    resp = json.load(sys.stdin)
except Exception:
    print("reader から不正な応答が返りました")
    sys.exit(0)
if not resp.get("ok"):
    print("同定を実行できませんでした:", resp.get("error", "不明なエラー"))
    sys.exit(0)

# 保存された JSON を特定する (file / jpg / json のいずれの返し方
# でも、.json / .jpg / 拡張子なしのいずれでも受けられるようにする)
base = resp.get("file") or resp.get("json") or resp.get("jpg") or ""
stem = base
for ext in (".json", ".jpg"):
    if stem.endswith(ext):
        stem = stem[: -len(ext)]
json_path = os.path.join("logs", stem + ".json")
for _ in range(10):
    if os.path.exists(json_path):
        break
    time.sleep(0.5)

data = None
if stem and os.path.exists(json_path):
    try:
        with open(json_path) as f:
            data = json.load(f)
    except Exception:
        data = None

lines = []
if data:
    mine = data.get("mine") or []
    opp = data.get("oppTeam") or []
    if mine:
        name = data.get("trainerMine") or "You"
        lines.append(f"{name}\x27s team: " + " / ".join(mine))
    if opp:
        name = data.get("trainerOpp") or "Opponent"
        lines.append(f"{name}\x27s team: " + " / ".join(opp))
if not lines:
    lines = resp.get("lines") or (data or {}).get("lines") or []
for line in lines:
    print(line)
if stem:
    print(f"(保存: logs/{stem}.jpg, logs/{stem}.json — 自動で送信されます)")
'
}

while true; do
  echo ""
  echo "見せ合い画面を表示して sキーを押してください (qで終了)"
  if ! read -rsn1 key; then break; fi
  case "$key" in
    s|S) do_capture ;;
    q|Q) break ;;
  esac
done
echo "終了します"
