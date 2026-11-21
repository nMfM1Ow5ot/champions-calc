#!/bin/bash
# 見せ合い画面の同定テスト (Mac用ターミナル)
# 起動すると、reader と serve.py が動いていなければ自動で起動し、
# 準備ができたらキー待ちになる。見せ合い画面を表示した状態で
# sキーを押すと、その時点の画面を撮影して見せ合い同定を行い、
# 結果を Showdown のヘッダー形式 (<名前>'s team: …) で表示する。
# 撮影画像と検出結果は logs/ に preview_test_<日時>.jpg/.json として
# 保存され、serve.py が自動で送信する (ログ分析側で精度を分析する)。
# qキーで終了する。このスクリプトが起動した reader / serve.py は
# 終了時に一緒に止める (元から動いていたものには触れない)。ただし
# serve.py を起動した場合は、撮影分のアップロード完了 (serve.py が
# ログに送信完了を出すまで) を待ってから止める。撮影直後に終了すると
# 送信サイクル (約30秒ごと) の前に serve.py が落ちて、撮影分が
# 未送信のまま残る事故があったため。
cd "$(dirname "$0")"

READER_LOG="preview_test_reader.log"
SERVE_LOG="preview_test_serve.log"
STARTED=()
SERVE_STARTED=0
CAPTURED=()
CAPTURED_LOG_OFFSET=()
UPLOAD_WAIT_SEC="${PREVIEW_TEST_UPLOAD_WAIT_SEC:-120}"

# ポートが開いているか (接続できるか) だけを見る。/previewtest への
# HTTP リクエストは撮影そのものを引き起こすため、起動確認には使わない
port_open() {
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

# 撮影分のアップロード完了を待つ。serve.py は送信したファイルごとに
# 「見せ合いテストの結果を送信しました: <ファイル名>」をログへ出すため、
# 撮影時点のログ末尾以降にその行が現れたかで完了を判定する
wait_for_uploads() {
  if [ "$SERVE_STARTED" -ne 1 ] || [ ${#CAPTURED[@]} -eq 0 ]; then
    return 0
  fi
  local deadline=$((SECONDS + UPLOAD_WAIT_SEC)) announced=0
  while [ $SECONDS -lt $deadline ]; do
    local remaining=0 i stem off ext
    for i in "${!CAPTURED[@]}"; do
      stem="${CAPTURED[$i]}"
      off="${CAPTURED_LOG_OFFSET[$i]}"
      for ext in jpg json; do
        if ! tail -c +$((off + 1)) "$SERVE_LOG" 2>/dev/null | grep -q "送信しました: ${stem}.${ext}"; then
          remaining=$((remaining + 1))
        fi
      done
    done
    if [ "$remaining" -eq 0 ]; then
      echo "見せ合いテストの送信が完了しました"
      return 0
    fi
    if [ "$announced" -eq 0 ]; then
      echo "見せ合いテストの送信完了を待っています (最大 ${UPLOAD_WAIT_SEC} 秒)…"
      announced=1
    fi
    sleep 2
  done
  echo "送信完了を確認できませんでした。撮影ファイルは logs/ に残っており、次回 start_all.sh / preview_test.sh の起動時に送信されます"
}

# このスクリプトが起動したプロセスだけを止める。run_reader.sh 経由の
#場合はその子 (swift 本体) も一緒に止める
cleanup() {
  wait_for_uploads
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
  # 制御端末 (/dev/tty) につなぐ。見せ合いテスト結果の送信は、この
  # スクリプトが起動した serve.py でのみ有効になるよう環境変数で
  # 明示する (通常起動の serve.py は過去のテスト結果を送らない)
  if [ -e /dev/tty ]; then
    CHAMPIONS_PREVIEW_TEST_SESSION=1 python3 serve.py < /dev/tty >> "$SERVE_LOG" 2>&1 &
  else
    CHAMPIONS_PREVIEW_TEST_SESSION=1 python3 serve.py >> "$SERVE_LOG" 2>&1 &
  fi
  STARTED+=($!)
  SERVE_STARTED=1
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
  # 撮影時点の serve.py ログ末尾位置。アップロード完了の判定は
  # この位置以降のログだけを見る (撮影前に末尾を押さえるのは、
  # 撮影直後のサイクルで送られた場合に行を取りこぼさないため)
  local log_offset=0
  if [ -f "$SERVE_LOG" ]; then
    log_offset=$(wc -c < "$SERVE_LOG")
  fi
  # 見せ合いテスト結果の送信を、動いている serve.py で有効化する
  # (通常起動の serve.py はテスト結果を送らないための明示スイッチ。
  # このスクリプトが起動した serve.py は環境変数でも有効化済み。
  # serve.py の自動再起動で有効化が落ちた場合に備え、撮影のたびに
  # 送り直す)
  curl -s --max-time 5 -X POST "http://localhost:8765/preview_test_session" > /dev/null 2>&1 || true
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

  # 終了時にアップロード完了を待てるよう、撮影したファイル名と
  # その時点の serve.py ログ末尾位置を記録しておく
  local stem
  stem=$(echo "$RESP" | python3 -c '
import json, sys
try:
    resp = json.load(sys.stdin)
except Exception:
    sys.exit(0)
base = resp.get("file") or resp.get("json") or resp.get("jpg") or ""
for ext in (".json", ".jpg"):
    if base.endswith(ext):
        base = base[: -len(ext)]
if base:
    print(base)
' 2>/dev/null)
  if [ -n "$stem" ]; then
    CAPTURED+=("$stem")
    CAPTURED_LOG_OFFSET+=($log_offset)
  fi
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
