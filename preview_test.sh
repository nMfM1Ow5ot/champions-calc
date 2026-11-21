#!/bin/bash
# 見せ合い画面の同定テスト (Mac用ターミナル)
# 実行すると、その時点の画面を撮影して見せ合い同定を行い、結果を
# Showdown のヘッダー形式 (<名前>'s team: …) で表示する。
# 撮影画像と検出結果は logs/ に preview_test_<日時>.jpg/.json として
# 保存され、serve.py が自動で送信する (ログ分析側で精度を分析する)。
cd "$(dirname "$0")"

RESP=$(curl -s --max-time 90 "http://localhost:8899/previewtest")
RC=$?
if [ $RC -ne 0 ] || [ -z "$RESP" ]; then
  if [ $RC -eq 28 ]; then
    echo "同定が時間内に終わりませんでした。画面が見せ合い画面か確認して、もう一度実行してください。"
  else
    echo "reader に接続できませんでした。ダメ計 (start_all.sh) が起動しているか確認してください。"
  fi
  exit 1
fi

echo "$RESP" | python3 -c '
import json, os, sys, time

try:
    resp = json.load(sys.stdin)
except Exception:
    print("reader から不正な応答が返りました")
    sys.exit(1)
if not resp.get("ok"):
    print("同定を実行できませんでした:", resp.get("error", "不明なエラー"))
    sys.exit(1)

# 保存された JSON を特定する (file / jpg / json のいずれの返し方
# でも、.json / .jpg / 拡張子なしのいずれでも受けられるようにする)
base = resp.get("file") or resp.get("json") or resp.get("jpg") or ""
stem = base
for ext in (".json", ".jpg"):
    if stem.endswith(ext):
        stem = stem[: -len(ext)]
json_path = os.path.join("logs", stem + ".json")
jpg_path = os.path.join("logs", stem + ".jpg")
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
