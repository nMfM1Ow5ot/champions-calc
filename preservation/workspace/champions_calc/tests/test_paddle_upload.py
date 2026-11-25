#!/usr/bin/env python3
"""serve.py の PaddleOCR 証拠 (battle_<キー>_paddle.jsonl) の送信
組み込みのテスト (PaddleOCR 補助チャンネル化ステップ1)。

検証すること:
- battle_<キー>_paddle.jsonl は送信対象になり、その試合のキーに
  束ねられる (備考ゲートの対象)
- salvage キーにも束ねられる
- 関係ないファイル名は対象にならない

実行: python3 tests/test_paddle_upload.py (全て PASS で終了コード 0)
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "serve", os.path.join(HERE, "..", "serve.py"))
serve = importlib.util.module_from_spec(spec)
spec.loader.exec_module(serve)

failures = []


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        failures.append(name)


KEY = "20261123_021900"
NAME = f"battle_{KEY}_paddle.jsonl"

check("paddle.jsonl は送信対象", serve._is_upload_target(NAME))
check("試合キーに束ねられる", serve._battle_key(NAME) == KEY)
check("salvage キーにも束ねられる",
      serve._battle_key(f"battle_{KEY}_salvage_paddle.jsonl")
      == f"{KEY}_salvage")
check("無関係な jsonl は対象外",
      not serve._is_upload_target(f"battle_{KEY}_other.jsonl"))
check("無関係なファイルのキーは None",
      serve._battle_key("battle_20261123_021900_other.jsonl") is None)

print("ALL PASS" if not failures else f"FAILURES: {failures}")
sys.exit(0 if not failures else 1)
