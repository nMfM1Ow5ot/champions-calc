#!/usr/bin/env python3
# 編集状態の見える化のための小さなヘルパー (Muse 側の作業用。
# このファイル自体も .edit_state.json も、同期対象にも zip にも含めない)。
#
# 使い方:
#   python3 edit_lock.py claim <ファイル> <担当チャット id> [メモ...]
#   python3 edit_lock.py release <ファイル> [担当チャット id]
#   python3 edit_lock.py status
#
# 状態は .edit_state.json に {"claims": [{file, chat, started, memo}]} で
# 記録する。手編集の事故を避けるため、編集はこのヘルパー経由で行う。
# push_update.py はこのファイルを読み、push 対象ファイルに他チャットの
# 記録があれば中止し、対象外の記録は警告のみで続行する。
import json
import os
import sys
from datetime import datetime, timezone, timedelta

BASE = os.path.dirname(os.path.abspath(__file__))
STATE = os.path.join(BASE, ".edit_state.json")
JST = timezone(timedelta(hours=9))
STALE_HOURS = 3


def load():
    if not os.path.exists(STATE):
        return {"claims": []}
    try:
        doc = json.load(open(STATE, encoding="utf-8"))
    except Exception as e:
        raise SystemExit(f".edit_state.json が壊れています: {e}。"
                         "内容を確認して直すか、削除してください")
    if not isinstance(doc, dict) or not isinstance(doc.get("claims"), list):
        raise SystemExit(".edit_state.json の形式が想定と違います。"
                         "内容を確認して直すか、削除してください")
    return doc


def save(doc):
    tmp = STATE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
    os.replace(tmp, STATE)


def parse_started(claim):
    try:
        return datetime.fromisoformat(claim.get("started", ""))
    except Exception:
        return None


def cmd_claim(argv):
    if len(argv) < 2:
        raise SystemExit("使い方: edit_lock.py claim <ファイル> "
                         "<担当チャット id> [メモ...]")
    rel, chat = argv[0], argv[1]
    memo = " ".join(argv[2:])
    doc = load()
    others = [c for c in doc["claims"]
              if c["file"] == rel and c["chat"] != chat]
    for c in others:
        print(f"警告: {rel} には既に {c['chat']} の編集中の記録があります"
              f" (開始 {c.get('started', '?')})。同時編集になっていないか"
              "確認してください")
    doc["claims"] = [c for c in doc["claims"]
                     if not (c["file"] == rel and c["chat"] == chat)]
    doc["claims"].append({
        "file": rel, "chat": chat,
        "started": datetime.now(JST).isoformat(timespec="seconds"),
        "memo": memo,
    })
    save(doc)
    print(f"記録しました: {rel} を {chat} が編集中"
          + (f" ({memo})" if memo else ""))


def cmd_release(argv):
    if len(argv) < 1:
        raise SystemExit("使い方: edit_lock.py release <ファイル> "
                         "[担当チャット id]")
    rel = argv[0]
    chat = argv[1] if len(argv) > 1 else None
    doc = load()
    kept = [c for c in doc["claims"]
            if not (c["file"] == rel and (chat is None or c["chat"] == chat))]
    removed = len(doc["claims"]) - len(kept)
    doc["claims"] = kept
    save(doc)
    if removed:
        print(f"解除しました: {rel} の編集中の記録 {removed} 件")
    else:
        print(f"{rel} に解除する記録はありませんでした")


def cmd_status(argv):
    doc = load()
    if not doc["claims"]:
        print("編集中の記録はありません")
        return
    now = datetime.now(JST)
    for c in sorted(doc["claims"], key=lambda c: (c["file"], c["chat"])):
        started = parse_started(c)
        age = ""
        stale = ""
        if started is not None:
            hours = (now - started).total_seconds() / 3600
            age = f"開始 {c['started']} ({hours:.1f} 時間前)"
            if hours >= STALE_HOURS:
                stale = " [古い可能性あり]"
        else:
            age = f"開始 {c.get('started', '?')}"
        memo = f" — {c['memo']}" if c.get("memo") else ""
        print(f"{c['file']}: {c['chat']} が編集中、{age}{memo}{stale}")


def main():
    if len(sys.argv) < 2:
        raise SystemExit("使い方: edit_lock.py claim|release|status ...")
    cmd, argv = sys.argv[1], sys.argv[2:]
    if cmd == "claim":
        cmd_claim(argv)
    elif cmd == "release":
        cmd_release(argv)
    elif cmd == "status":
        cmd_status(argv)
    else:
        raise SystemExit(f"不明なサブコマンドです: {cmd} "
                         "(claim / release / status)")


if __name__ == "__main__":
    main()
