#!/usr/bin/env python3
"""serve.py のログ送信の再開性 (失敗したサイクルは未送信分から再開)。

対象の事故 (2026-11-22、ユーザーのターミナル報告):
battle_20261122_181745 の送信が途中で HTTP 409 により失敗し、
再試行時に calclog.json から先頭まで戻って全ファイルを送り直した。

対策の検証:
- ファイル単位の進捗 (uploaded.json + index_pending.json) が送信の
  都度永続化され、失敗したサイクルの次回は未送信分だけを送る
- ファイル PUT の 409 は sha を取り直して 1 回だけ再試行する
- 目録 PUT の 409 は目録を取り直し、このサイクルで送った分だけを
  重ねて 1 回だけ再試行する
- 目録への反映が失敗したサイクルでは送信済みの記録を付けず、
  次のサイクルでファイルの再送なしに目録だけを修復して記録する
- 全ファイルがそろった時点で完了表示と記録が行われる

実行: python3 tests/test_upload_resume.py (全て PASS で終了コード 0)
"""
import hashlib
import importlib.util
import io
import json
import os
import sys
import tempfile
import urllib.error
from contextlib import redirect_stdout
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "serve", os.path.join(HERE, "..", "serve.py"))
serve = importlib.util.module_from_spec(spec)
spec.loader.exec_module(serve)
# 自動送信は出荷状態では無効化されている (2026-11-23)。この
# スイートは保持された送信機構そのものを検証するため、明示的
# に有効化してから走らせる
serve._AUTO_UPLOAD_ENABLED = True

JST = timezone(timedelta(hours=9))
K = "20261122_235959"
FILES = {
    f"battle_{K}_calclog.json": b'{"kind":"calc-log"}',
    f"battle_{K}_final.log": b"log body |start",
    f"battle_{K}_final_protocol.log": b"protocol |start",
    f"battle_{K}_note.txt": b"",
}

failures = []


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        failures.append(name)


def http_err(code):
    return urllib.error.HTTPError("https://api.github.com/x", code,
                                  f"err {code}", None, None)


class FakeGH:
    """remote: path -> bytes。fail_plan: path -> [raise する例外...]"""

    def __init__(self):
        self.remote = {"logs_enc/index.json":
                       json.dumps({"files": []}).encode()}
        self.puts = []
        self.fail_plan = {}

    def get_file(self, path, token):
        if path in self.remote:
            return self.remote[path], "sha:" + path
        return None, None

    def put_file(self, path, data, token, msg, sha=None):
        self.puts.append(path)
        plan = self.fail_plan.get(path)
        if plan:
            raise plan.pop(0)
        self.remote[path] = data
        return "sha:" + path

    def index_names(self):
        idx = json.loads(self.remote["logs_enc/index.json"].decode())
        return sorted(e["name"] for e in idx["files"])

    def put_count(self, path):
        return self.puts.count(path)


def setup(tmp):
    gh = FakeGH()
    serve.LOG_DIR = tmp
    serve.LOG_STATE_PATH = os.path.join(tmp, "uploaded.json")
    serve._log_token = lambda: "token"
    serve._gh_get_file = gh.get_file
    serve._gh_put_file = gh.put_file
    serve._encrypt_log = lambda data: b"enc:" + data
    serve._log_last_error = ""
    serve._note_prompt_waiting = False
    serve._upload_battle_deferred = False
    for n, data in FILES.items():
        with open(os.path.join(tmp, n), "wb") as f:
            f.write(data)
    return gh


def cycle():
    buf = io.StringIO()
    with redirect_stdout(buf):
        serve.upload_logs_once(session_only=False)
    return buf.getvalue()


def sent_battles(tmp):
    p = os.path.join(tmp, "sent_battles.json")
    if not os.path.exists(p):
        return set()
    return set(json.loads(open(p).read()))


# S1: 途中のファイルで失敗 -> 次のサイクルは未送信分だけを送る
tmp = tempfile.mkdtemp()
gh = setup(tmp)
proto_path = f"logs_enc/battle_{K}_final_protocol.log.enc"
gh.fail_plan[proto_path] = [http_err(500)]
cycle()
check("S1 cycle1: index not updated after mid-loop failure",
      gh.index_names() == [])
check("S1 cycle1: battle not marked sent", K not in sent_battles(tmp))
state = json.loads(open(os.path.join(tmp, "uploaded.json")).read())
check("S1 cycle1: progress persisted for the first two files",
      state.get(f"battle_{K}_calclog.json")
      == hashlib.sha256(FILES[f"battle_{K}_calclog.json"]).hexdigest()
      and state.get(f"battle_{K}_final.log")
      == hashlib.sha256(FILES[f"battle_{K}_final.log"]).hexdigest())
out = cycle()
check("S1 cycle2: uploaded files are not re-sent",
      gh.put_count(f"logs_enc/battle_{K}_calclog.json.enc") == 1
      and gh.put_count(f"logs_enc/battle_{K}_final.log.enc") == 1)
check("S1 cycle2: remaining files sent",
      gh.put_count(proto_path) == 2
      and gh.put_count(f"logs_enc/battle_{K}_note.txt.enc") == 1)
check("S1 cycle2: index complete", gh.index_names() == sorted(FILES))
check("S1 cycle2: battle marked sent", K in sent_battles(tmp))
check("S1 cycle2: completion line announced once",
      out.count(f"battle_{K} の試合ログをすべて送信しました") == 1)

# S2: ファイル PUT の 409 は sha を取り直して再試行し、その場で完了する
tmp = tempfile.mkdtemp()
gh = setup(tmp)
calc_path = f"logs_enc/battle_{K}_calclog.json.enc"
gh.fail_plan[calc_path] = [http_err(409)]
cycle()
check("S2: 409 retried and cycle completed",
      gh.put_count(calc_path) == 2 and gh.index_names() == sorted(FILES))
check("S2: battle marked sent", K in sent_battles(tmp))

# S3: 目録 PUT の 409 は目録を取り直して重ねて再試行する
tmp = tempfile.mkdtemp()
gh = setup(tmp)
gh.fail_plan["logs_enc/index.json"] = [http_err(409)]
cycle()
check("S3: index 409 merged and retried",
      gh.put_count("logs_enc/index.json") == 2
      and gh.index_names() == sorted(FILES))
check("S3: files sent exactly once",
      all(gh.put_count(f"logs_enc/{n}.enc") == 1 for n in FILES))
check("S3: battle marked sent", K in sent_battles(tmp))

# S4: 目録 PUT の失敗時は記録せず、次回は目録だけを修復して記録する
tmp = tempfile.mkdtemp()
gh = setup(tmp)
gh.fail_plan["logs_enc/index.json"] = [http_err(500)]
cycle()
check("S4 cycle1: files uploaded but index empty",
      gh.index_names() == []
      and all(f"logs_enc/{n}.enc" in gh.remote for n in FILES))
check("S4 cycle1: battle not marked sent", K not in sent_battles(tmp))
puts_before = list(gh.puts)
out = cycle()
file_puts = [p for p in gh.puts[len(puts_before):]
             if p != "logs_enc/index.json"]
check("S4 cycle2: no file is re-sent", file_puts == [])
check("S4 cycle2: index repaired", gh.index_names() == sorted(FILES))
check("S4 cycle2: battle marked sent", K in sent_battles(tmp))
check("S4 cycle2: completion line announced",
      f"battle_{K} の試合ログをすべて送信しました" in out)

print("FAILURES:", failures if failures else "none")
sys.exit(1 if failures else 0)
