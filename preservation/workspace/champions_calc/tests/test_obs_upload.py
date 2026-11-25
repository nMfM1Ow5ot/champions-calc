#!/usr/bin/env python3
"""serve.py の生観測アーカイブ (battle_<キー>_obs.jsonl) の送信
組み込みのテスト (改善計画フェーズ0)。

検証すること:
- battle_<キー>_obs.jsonl は送信対象になり、その試合のキーに
  束ねられる (備考ゲートの対象: 備考ファイルが無ければ備考待ちに
  なり、あれば待ちにならない)
- salvage キーにも束ねられる

実行: python3 tests/test_obs_upload.py (全て PASS で終了コード 0)
"""
import importlib.util
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "serve", os.path.join(HERE, "..", "serve.py"))
serve = importlib.util.module_from_spec(spec)
spec.loader.exec_module(serve)
# 備考ゲートは出荷状態では無効化されている (2026-11-23)。この
# スイートは備考待ちを含む従来の送信経路を検証するため、明示的
# に有効化してから走らせる
serve._NOTE_GATE_ENABLED = True

failures = []


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        failures.append(name)


KEY = "20261122_051707"
NAME = f"battle_{KEY}_obs.jsonl"

# --- 送信対象とキーの束ね ---
check("obs.jsonl は送信対象", serve._is_upload_target(NAME))
check("試合キーに束ねられる", serve._battle_key(NAME) == KEY)
check("salvage キーにも束ねられる",
      serve._battle_key(f"battle_{KEY}_salvage_obs.jsonl")
      == f"{KEY}_salvage")
check("関係ない jsonl は送信対象でない",
      not serve._is_upload_target("battle_20261122_051707_notes.jsonl"))

# --- 備考ゲート (その試合の一式として扱われる) ---
tmp = tempfile.mkdtemp()
serve.LOG_DIR = tmp
with open(os.path.join(tmp, f"battle_{KEY}_final.log"), "w") as f:
    f.write("Turn 1\n")
with open(os.path.join(tmp, NAME), "w") as f:
    f.write('{"t": 1, "frame": 1, "pass": "boxes", "region": [], "boxes": []}\n')
pending = serve.list_pending_log_notes()
check("備考が無ければ備考待ちに含まれる",
      any(p["key"] == KEY for p in pending))
with open(os.path.join(tmp, f"battle_{KEY}_note.txt"), "w") as f:
    f.write("")
pending = serve.list_pending_log_notes()
check("備考があれば備考待ちに含まれない",
      not any(p["key"] == KEY for p in pending))

print("FAILURES:", failures if failures else "none")
sys.exit(1 if failures else 0)
